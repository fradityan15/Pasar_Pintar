import { createClient } from "npm:@supabase/supabase-js@2"
import { courierCodes, rajaongkirRequest } from "../_shared/rajaongkir.ts"
import { handleOptions, jsonResponse } from "../_shared/http.ts"

type SellerRecord = {
  id: string
  name: string
  rajaongkir_origin_area_id: string | null
  shipping_providers: unknown
  status: string
  is_active: boolean
  is_verified: boolean
}

type ProductRecord = {
  id: string
  name: string
  price: number
  weight_gram: number
  is_active: boolean
  umkm_id: string
  umkm: SellerRecord | SellerRecord[] | null
}

type CartItemRecord = {
  product_id: string
  quantity: number
  products: ProductRecord | ProductRecord[] | null
}

type RateChoice = {
  umkm_id: string
  courier_code: string
  courier_name: string
  service_code: string
  service_name: string
  shipping_cost: number
  duration: string | null
}

type SellerGroup = {
  id: string
  name: string
  originAreaId: string
  courierCodes: string[]
  weight: number
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

function normalizeRate(raw: unknown, group: SellerGroup, requestedCourier: string): RateChoice[] {
  if (!isRecord(raw)) return []
  const costValue = isRecord(raw.cost) ? raw.cost.value : raw.cost
  const cost = Number(costValue)
  const serviceCode = typeof raw.service === "string" ? raw.service.trim() : ""
  if (!Number.isSafeInteger(cost) || cost <= 0 || !serviceCode) return []

  const courierCode = typeof raw.code === "string" ? raw.code.toLowerCase() : requestedCourier
  const duration = isRecord(raw.cost) ? raw.cost.etd : raw.etd
  return [{
    umkm_id: group.id,
    courier_code: courierCode,
    courier_name: typeof raw.name === "string" ? raw.name : courierCode.toUpperCase(),
    service_code: serviceCode,
    service_name: typeof raw.description === "string" ? raw.description : serviceCode,
    shipping_cost: cost,
    duration: typeof duration === "string" ? duration : null,
  }]
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
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
    if (!supabaseUrl || !anonKey || !serviceKey) throw new Error("Konfigurasi Supabase Edge Function belum lengkap.")

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const { data: userResult, error: authError } = await userClient.auth.getUser(token)
    if (authError || !userResult.user) return jsonResponse({ error: "Sesi login tidak valid." }, 401)

    const body = await request.json().catch(() => null)
    const addressId = body?.address_id
    const productIds = body?.product_ids
    if (
      typeof addressId !== "string" ||
      !/^[0-9a-f-]{36}$/i.test(addressId) ||
      !Array.isArray(productIds) ||
      !productIds.length ||
      productIds.length > 100 ||
      !productIds.every((id: unknown) => typeof id === "string" && /^[0-9a-f-]{36}$/i.test(id)) ||
      new Set(productIds).size !== productIds.length
    ) return jsonResponse({ error: "Alamat atau daftar produk tidak valid." }, 400)

    const service = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const { data: address, error: addressError } = await service.from("addresses")
      .select("id, user_id, recipient_name, phone, street, city, province, postal_code, rajaongkir_area_id")
      .eq("id", addressId)
      .maybeSingle()
    if (addressError) throw addressError
    if (!address || address.user_id !== userResult.user.id) {
      return jsonResponse({ error: "Alamat pengiriman tidak ditemukan." }, 404)
    }
    const destinationAreaId = typeof address.rajaongkir_area_id === "string"
      ? address.rajaongkir_area_id.trim()
      : ""
    if (!destinationAreaId) {
      return jsonResponse({ error: "Pilih wilayah tujuan RajaOngkir pada alamat pengiriman terlebih dahulu." }, 422)
    }

    const { data: cartItems, error: cartError } = await service.from("cart_items")
      .select("product_id, quantity, products!inner(id, name, price, weight_gram, is_active, umkm_id, umkm!inner(id, name, rajaongkir_origin_area_id, shipping_providers, status, is_active, is_verified))")
      .eq("user_id", userResult.user.id)
      .in("product_id", productIds)
    if (cartError) throw cartError
    if (!cartItems || cartItems.length !== productIds.length) {
      return jsonResponse({ error: "Sebagian produk tidak lagi tersedia di keranjang." }, 409)
    }

    const groups = new Map<string, SellerGroup>()
    const snapshot: Array<Record<string, string | number>> = []
    for (const cartItem of cartItems as CartItemRecord[]) {
      const product = Array.isArray(cartItem.products) ? cartItem.products[0] : cartItem.products
      const seller = Array.isArray(product?.umkm) ? product.umkm[0] : product?.umkm
      if (!product || !seller) return jsonResponse({ error: "Data produk atau toko tidak lengkap." }, 409)
      if (!product.is_active || seller.status !== "active" || !seller.is_active || !seller.is_verified) {
        return jsonResponse({ error: `Produk "${product.name}" atau tokonya belum tersedia untuk dibeli.` }, 409)
      }
      if (!Number.isInteger(product.weight_gram) || product.weight_gram <= 0) {
        return jsonResponse({ error: `Berat produk "${product.name}" belum diisi dengan benar.` }, 422)
      }
      const originAreaId = typeof seller.rajaongkir_origin_area_id === "string"
        ? seller.rajaongkir_origin_area_id.trim()
        : ""
      if (!originAreaId) {
        return jsonResponse({ error: `Toko "${seller.name}" belum memilih wilayah asal RajaOngkir.` }, 422)
      }
      let group = groups.get(seller.id)
      if (!group) {
        group = {
          id: seller.id,
          name: seller.name,
          originAreaId,
          courierCodes: courierCodes(seller.shipping_providers),
          weight: 0,
        }
        groups.set(seller.id, group)
      }
      group.weight += product.weight_gram * cartItem.quantity
      snapshot.push({
        product_id: product.id,
        quantity: cartItem.quantity,
        price: Number(product.price),
        weight_gram: product.weight_gram,
        umkm_id: seller.id,
        origin_area_id: originAreaId,
      })
    }
    snapshot.sort((a, b) => String(a.product_id).localeCompare(String(b.product_id)))

    const choicesBySeller: RateChoice[][] = []
    for (const group of [...groups.values()].sort((a, b) => a.id.localeCompare(b.id))) {
      if (!group.courierCodes.length) {
        return jsonResponse({ error: `Toko "${group.name}" belum memilih kurir yang didukung.` }, 422)
      }
      const params = new URLSearchParams({
        origin: group.originAreaId,
        destination: destinationAreaId,
        weight: String(group.weight),
        courier: group.courierCodes.join(":"),
        price: "lowest",
      })
      let response: Response
      try {
        response = await rajaongkirRequest("/calculate/domestic-cost", {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body: params.toString(),
        })
      } catch (error) {
        console.error("API tarif RajaOngkir tidak dapat dijangkau:", error)
        return jsonResponse({ error: "Tarif pengiriman sedang tidak tersedia. Coba lagi nanti." }, 503)
      }

      const providerBody: unknown = await response.json().catch(() => null)
      if (!response.ok || !isRecord(providerBody) || !Array.isArray(providerBody.data)) {
        const providerMeta = isRecord(providerBody) && isRecord(providerBody.meta)
          ? providerBody.meta
          : null
        const providerMessage = typeof providerMeta?.message === "string"
          ? providerMeta.message.slice(0, 300)
          : null
        console.error("API tarif RajaOngkir menolak permintaan:", {
          status: response.status,
          providerCode: providerMeta?.code ?? null,
          providerMessage,
        })
        return jsonResponse({
          error: providerMessage
            ? `RajaOngkir menolak tarif (HTTP ${response.status}): ${providerMessage}`
            : `RajaOngkir menolak permintaan tarif (HTTP ${response.status}). Periksa log Edge Function.`,
        }, 502)
      }
      const groupChoices = providerBody.data.flatMap((rate) =>
        normalizeRate(rate, group, group.courierCodes[0]),
      )
      const choices = groupChoices
        .sort((a, b) => a.shipping_cost - b.shipping_cost)
        .slice(0, 8)
      if (!choices.length) {
        const providerMeta = isRecord(providerBody.meta) ? providerBody.meta : null
        const firstResult = providerBody.data[0]
        console.error("RajaOngkir tidak mengembalikan tarif yang dapat digunakan:", {
          providerCode: providerMeta?.code ?? null,
          providerMessage: typeof providerMeta?.message === "string"
            ? providerMeta.message.slice(0, 300)
            : null,
          resultCount: providerBody.data.length,
          firstResultKeys: isRecord(firstResult) ? Object.keys(firstResult) : [],
          courierCodes: group.courierCodes,
          weightGram: group.weight,
        })
        return jsonResponse({
          error: `Tidak ada tarif kurir tersedia dari toko "${group.name}" ke wilayah ini. Periksa wilayah asal toko, kurir yang diaktifkan, dan berat paket.`,
        }, 422)
      }
      choicesBySeller.push(choices)
    }

    let combinations: RateChoice[][] = [[]]
    for (const choices of choicesBySeller) {
      combinations = combinations.flatMap((previous) =>
        choices.map((choice) => [...previous, choice]).slice(0, 40),
      ).slice(0, 40)
    }
    const options = combinations.map((shipments) => ({
      id: crypto.randomUUID(),
      shipping_cost: shipments.reduce((total, shipment) => total + shipment.shipping_cost, 0),
      shipments,
    })).sort((a, b) => a.shipping_cost - b.shipping_cost)
    if (options.some((option) => !Number.isSafeInteger(option.shipping_cost))) {
      return jsonResponse({ error: "Tarif RajaOngkir tidak valid." }, 502)
    }

    const { data: quote, error: quoteError } = await service.from("shipping_quotes")
      .insert({
        user_id: userResult.user.id,
        address_id: address.id,
        item_snapshot: {
          destination_area_id: destinationAreaId,
          items: snapshot,
        },
        options,
        expires_at: new Date(Date.now() + 10 * 60 * 1000).toISOString(),
      })
      .select("id, expires_at")
      .single()
    if (quoteError) throw quoteError

    return jsonResponse({
      quote_id: quote.id,
      expires_at: quote.expires_at,
      options: options.map((option) => ({
        ...option,
        shipments: option.shipments.map((shipment) => ({
          ...shipment,
          seller_name: groups.get(shipment.umkm_id)?.name,
        })),
      })),
    })
  } catch (error) {
    console.error("Gagal menghitung tarif RajaOngkir:", error)
    return jsonResponse({ error: "Tarif pengiriman belum dapat dihitung. Coba lagi nanti." }, 500)
  }
})
