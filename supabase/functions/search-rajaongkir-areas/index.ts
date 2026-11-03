import { createClient } from "npm:@supabase/supabase-js@2"
import { rajaongkirRequest } from "../_shared/rajaongkir.ts"
import { handleOptions, jsonResponse } from "../_shared/http.ts"

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

function areaName(area: Record<string, unknown>): string {
  for (const key of ["subdistrict_name", "village_name", "district_name", "city_name", "name", "label"]) {
    if (typeof area[key] === "string" && area[key].trim()) return area[key].trim()
  }
  return ""
}

function areaLabel(area: Record<string, unknown>, name: string): string {
  if (typeof area.label === "string" && area.label.trim()) return area.label.trim()
  return [
    name,
    area.district_name,
    area.city_name,
    area.province_name,
    area.zip_code ?? area.postal_code,
  ]
    .filter((part): part is string | number => typeof part === "string" || typeof part === "number")
    .map(String)
    .filter(Boolean)
    .join(", ")
}

Deno.serve(async (request) => {
  const earlyResponse = handleOptions(request)
  if (earlyResponse) return earlyResponse

  try {
    const authorization = request.headers.get("Authorization")
    const token = authorization?.match(/^Bearer\s+(.+)$/i)?.[1]
    if (!token) return jsonResponse({ error: "Sesi login tidak valid." }, 401)

    const supabaseUrl = Deno.env.get("SUPABASE_URL")
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")
    if (!supabaseUrl || !anonKey) throw new Error("Konfigurasi Supabase Edge Function belum lengkap.")

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const { data: userResult, error: authError } = await userClient.auth.getUser(token)
    if (authError || !userResult.user) return jsonResponse({ error: "Sesi login tidak valid." }, 401)

    const body = await request.json().catch(() => null)
    const query = typeof body?.query === "string" ? body.query.trim() : ""
    if (query.length < 2 || query.length > 80) {
      return jsonResponse({ error: "Kata kunci wilayah harus terdiri dari 2 sampai 80 karakter." }, 400)
    }

    const normalizedQuery = query.replace(
      /^(?:kelurahan|desa|kecamatan|kabupaten|kota|provinsi)\s+/i,
      "",
    ).trim()
    const searchQueries = [...new Set([normalizedQuery, query].filter((value) => value.length >= 2))]
    let areas: Array<{ id: string; name: string; label: string }> = []
    for (const [index, search] of searchQueries.entries()) {
      const params = new URLSearchParams({ search, limit: "10", offset: "0" })
      let response: Response
      try {
        response = await rajaongkirRequest(`/destination/domestic-destination?${params.toString()}`)
      } catch (error) {
        console.error("API pencarian wilayah RajaOngkir tidak dapat dijangkau:", error)
        return jsonResponse({ error: "Layanan pencarian wilayah sedang tidak tersedia. Coba lagi." }, 503)
      }

      const providerBody: unknown = await response.json().catch(() => null)
      if (!response.ok || !isRecord(providerBody) || !Array.isArray(providerBody.data)) {
        const providerMeta = isRecord(providerBody) && isRecord(providerBody.meta)
          ? providerBody.meta
          : null
        const providerMessage = typeof providerMeta?.message === "string"
          ? providerMeta.message.slice(0, 300)
          : null
        console.error("API pencarian wilayah RajaOngkir menolak permintaan:", {
          status: response.status,
          providerCode: providerMeta?.code ?? null,
          providerMessage,
        })
        if (response.status === 400 && index < searchQueries.length - 1) continue
        return jsonResponse({
          error: `RajaOngkir menolak pencarian wilayah (HTTP ${response.status}). Periksa log Edge Function.`,
        }, 502)
      }

      areas = providerBody.data.flatMap((rawArea) => {
        if (!isRecord(rawArea) || (typeof rawArea.id !== "string" && typeof rawArea.id !== "number")) return []
        const id = String(rawArea.id)
        const name = areaName(rawArea)
        if (!name) return []
        return [{ id, name, label: areaLabel(rawArea, name) }]
      })
      if (areas.length) break
    }

    return jsonResponse({ areas })
  } catch (error) {
    console.error("Kesalahan fungsi search-rajaongkir-areas:", error)
    return jsonResponse({ error: "Pencarian wilayah gagal diproses." }, 500)
  }
})
