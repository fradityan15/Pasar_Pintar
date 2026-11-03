import { createClient } from "npm:@supabase/supabase-js@2"
import { handleOptions, jsonResponse } from "../_shared/http.ts"

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
    const orderId = body?.order_id
    if (typeof orderId !== "string" || !/^[0-9a-f-]{36}$/i.test(orderId)) {
      return jsonResponse({ error: "ID pesanan tidak valid." }, 400)
    }

    const { data: access, error: accessError } = await userClient.from("orders")
      .select("id")
      .eq("id", orderId)
      .maybeSingle()
    if (accessError || !access) return jsonResponse({ error: "Pesanan tidak ditemukan atau tidak dapat diakses." }, 404)

    const { data: events, error: eventReadError } = await userClient.from("shipment_events")
      .select("id, courier, tracking_number, status, description, occurred_at")
      .eq("order_id", orderId)
      .order("occurred_at", { ascending: false })
    if (eventReadError) throw eventReadError
    return jsonResponse({
      events: events ?? [],
      warning: "Pelacakan otomatis kurir belum tersedia melalui integrasi RajaOngkir.",
    })
  } catch (error) {
    console.error("Gagal memuat pelacakan pengiriman:", error)
    return jsonResponse({ error: "Riwayat pelacakan belum dapat dimuat." }, 500)
  }
})
