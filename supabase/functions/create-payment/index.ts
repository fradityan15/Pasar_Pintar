import { createClient } from "npm:@supabase/supabase-js@2"
import { corsHeaders, handleOptions, jsonResponse } from "../_shared/http.ts"
import {
  authorizationHeader,
  getServerKey,
  MIDTRANS_API,
  parseAmount,
  parseMidtransTimestamp,
  safeQrUrl,
} from "../_shared/midtrans.ts"

type PaymentAttempt = {
  payment_id: string
  provider_ref: string
  amount: number | string
  method: "qris" | "va"
  bank_code: string
  status: "creating" | "unknown" | "pending" | "paid" | "failed" | "expired" | "paid_late"
  instructions: Record<string, unknown> | null
  expires_at: string | null
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
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      throw new Error("Konfigurasi Supabase Edge Function belum lengkap.")
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const { data: userResult, error: userError } = await userClient.auth.getUser(token)
    if (userError || !userResult.user) return jsonResponse({ error: "Sesi login tidak valid." }, 401)

    const body = await request.json().catch(() => null)
    const orderId = body?.order_id
    if (typeof orderId !== "string" || !/^[0-9a-f-]{36}$/i.test(orderId)) {
      return jsonResponse({ error: "ID pesanan tidak valid." }, 400)
    }

    const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const { data: order, error: orderError } = await serviceClient
      .from("orders")
      .select("id, user_id, total, status, payment_status, payment_expires_at, payment_methods(provider, category)")
      .eq("id", orderId)
      .maybeSingle()
    if (orderError) throw orderError
    if (!order || order.user_id !== userResult.user.id) {
      return jsonResponse({ error: "Pesanan tidak ditemukan." }, 404)
    }

    const method = Array.isArray(order.payment_methods)
      ? order.payment_methods[0]
      : order.payment_methods
    if (method?.provider !== "midtrans") {
      return jsonResponse({ error: "Pesanan ini tidak menggunakan pembayaran Midtrans." }, 400)
    }

    const syncOrderExpiry = async (providerExpiry: string | null) => {
      if (!providerExpiry) return
      const expiry = order.payment_expires_at
        ? Math.min(new Date(order.payment_expires_at).getTime(), new Date(providerExpiry).getTime())
        : new Date(providerExpiry).getTime()
      const { error: expiryError } = await serviceClient.from("orders")
        .update({ payment_expires_at: new Date(expiry).toISOString() })
        .eq("id", orderId)
      if (expiryError) throw expiryError
    }

    const { data: attemptData, error: attemptError } = await serviceClient.rpc(
      "begin_midtrans_payment",
      { p_order_id: orderId },
    )
    if (attemptError) {
      console.error("Gagal memulai pembayaran Midtrans:", attemptError.message)
      return jsonResponse({ error: "Pembayaran tidak dapat dimulai. Periksa status pesanan lalu coba lagi." }, 409)
    }
    const attempt = (Array.isArray(attemptData) ? attemptData[0] : attemptData) as PaymentAttempt | null
    if (!attempt) throw new Error("RPC begin_midtrans_payment tidak mengembalikan payment attempt.")

    if (attempt.status === "pending" && attempt.instructions) {
      await syncOrderExpiry(attempt.expires_at)
      return jsonResponse({
        payment_id: attempt.payment_id,
        status: attempt.status,
        method: attempt.method,
        amount: Number(attempt.amount),
        instructions: attempt.instructions,
        expires_at: attempt.expires_at,
      })
    }
    if (!["creating", "unknown", "pending"].includes(attempt.status)) {
      return jsonResponse({ error: "Pembayaran sedang diverifikasi. Muat ulang halaman beberapa saat lagi." }, 409)
    }

    const amount = parseAmount(String(attempt.amount))
    if (!amount) throw new Error("Nominal order dari database bukan nominal IDR bulat yang valid.")

    const serverKey = getServerKey()
    const requestBody = attempt.method === "qris"
      ? {
        payment_type: "qris",
        qris: { acquirer: "gopay" },
        transaction_details: { order_id: attempt.provider_ref, gross_amount: amount },
      }
      : {
        payment_type: "bank_transfer",
        bank_transfer: { bank: attempt.bank_code },
        transaction_details: { order_id: attempt.provider_ref, gross_amount: amount },
      }

    let response: Response
    try {
      response = await fetch(`${MIDTRANS_API}/${encodeURIComponent(attempt.provider_ref)}/status`, {
        method: "GET",
        headers: {
          Authorization: authorizationHeader(serverKey),
          Accept: "application/json",
        },
        signal: AbortSignal.timeout(15000),
      })
    } catch (error) {
      await serviceClient.from("payments")
        .update({ status: "unknown", raw_payload: { error: "provider_request_outcome_unknown" } })
        .eq("id", attempt.payment_id)
      console.error("Hasil request charge Midtrans tidak diketahui:", error)
      return jsonResponse({ error: "Status pembayaran sedang diverifikasi. Coba muat ulang halaman." }, 502)
    }

    let providerBody = await response.json().catch(() => null)
    if (response.status === 404) {
      try {
        response = await fetch(`${MIDTRANS_API}/charge`, {
          method: "POST",
          headers: {
            Authorization: authorizationHeader(serverKey),
            Accept: "application/json",
            "Content-Type": "application/json",
          },
          body: JSON.stringify(requestBody),
          signal: AbortSignal.timeout(15000),
        })
      } catch (error) {
        await serviceClient.from("payments")
          .update({ status: "unknown", raw_payload: { error: "provider_request_outcome_unknown" } })
          .eq("id", attempt.payment_id)
        console.error("Hasil request charge Midtrans tidak diketahui:", error)
        return jsonResponse({ error: "Status pembayaran sedang diverifikasi. Coba muat ulang halaman." }, 502)
      }
      providerBody = await response.json().catch(() => null)
    }

    if (!response.ok || !providerBody || providerBody.order_id !== attempt.provider_ref) {
      await serviceClient.from("payments")
        .update({
          status: response.status === 404 ? "failed" : "unknown",
          raw_payload: {
            http_status: response.status,
            status_code: providerBody?.status_code ?? null,
            status_message: providerBody?.status_message ?? null,
          },
        })
        .eq("id", attempt.payment_id)
      console.error("Midtrans menolak pembuatan transaksi:", response.status, providerBody?.status_code)
      return jsonResponse({ error: "Transaksi pembayaran tidak dapat dibuat. Silakan coba lagi." }, 502)
    }
    if (parseAmount(providerBody.gross_amount) !== amount) {
      await serviceClient.from("payments")
        .update({ status: "unknown", raw_payload: { error: "provider_amount_mismatch" } })
        .eq("id", attempt.payment_id)
      console.error("Nominal respons Midtrans tidak cocok dengan order.")
      return jsonResponse({ error: "Nominal transaksi tidak cocok. Hubungi pengelola toko." }, 409)
    }

    let instructions: Record<string, unknown>
    if (attempt.method === "qris") {
      const qrAction = providerBody.actions?.find(
        (action: { name?: string }) => action.name === "generate-qr-code",
      )
      const qrUrl = safeQrUrl(qrAction?.url)
      if (!qrUrl) throw new Error("Respons Midtrans tidak memiliki URL QRIS sandbox yang valid.")
      instructions = { qr_url: qrUrl }
    } else {
      const va = providerBody.va_numbers?.find(
        (entry: { bank?: string }) => entry.bank === attempt.bank_code,
      )
      const vaNumber = va?.va_number ?? providerBody.permata_va_number
      if (attempt.bank_code === "mandiri" && typeof providerBody.bill_key === "string") {
        instructions = {
          bank: attempt.bank_code,
          bill_key: providerBody.bill_key,
          biller_code: providerBody.biller_code ?? null,
        }
      } else {
        const accountNumber = vaNumber
        if (typeof accountNumber !== "string" || !accountNumber) {
          await serviceClient.from("payments")
            .update({ status: "unknown", raw_payload: { error: "missing_va_instruction" } })
            .eq("id", attempt.payment_id)
          throw new Error("Respons Midtrans tidak memiliki nomor Virtual Account.")
        }
        instructions = { bank: attempt.bank_code, va_number: accountNumber }
      }
    }

    const expiresAt = parseMidtransTimestamp(providerBody.expiry_time)
    const { error: saveError } = await serviceClient.from("payments")
      .update({
        status: "pending",
        provider_transaction_id: providerBody.transaction_id ?? null,
        instructions,
        expires_at: expiresAt,
        raw_payload: providerBody,
      })
      .eq("id", attempt.payment_id)
    if (saveError) {
      console.error("Gagal menyimpan respons pembayaran Midtrans:", saveError.message)
      return jsonResponse({ error: "Instruksi pembayaran belum dapat disimpan. Muat ulang untuk memeriksa status." }, 500)
    }

    await syncOrderExpiry(expiresAt)

    return jsonResponse({
      payment_id: attempt.payment_id,
      status: "pending",
      method: attempt.method,
      amount,
      instructions,
      expires_at: expiresAt,
    })
  } catch (error) {
    console.error("Create payment Midtrans gagal:", error)
    return jsonResponse({ error: "Terjadi kesalahan saat menyiapkan pembayaran." }, 500)
  }
})
