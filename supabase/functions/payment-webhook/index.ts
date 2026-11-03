import { createClient } from "npm:@supabase/supabase-js@2"
import { handleOptions, jsonResponse } from "../_shared/http.ts"
import {
  getServerKey,
  parseAmount,
  parseMidtransTimestamp,
  verifyNotificationSignature,
} from "../_shared/midtrans.ts"

Deno.serve(async (request) => {
  const earlyResponse = handleOptions(request)
  if (earlyResponse) return earlyResponse

  try {
    const rawBody = await request.text()
    if (rawBody.length > 64 * 1024) return jsonResponse({ error: "Payload terlalu besar." }, 413)

    let notification: Record<string, unknown>
    try {
      notification = JSON.parse(rawBody)
    } catch {
      return jsonResponse({ error: "Payload notifikasi tidak valid." }, 400)
    }

    const signatureValid = await verifyNotificationSignature(notification, getServerKey())
    if (!signatureValid) return jsonResponse({ error: "Signature notifikasi tidak valid." }, 401)

    const providerRef = notification.order_id
    const transactionId = notification.transaction_id
    const gatewayStatus = notification.transaction_status
    const amount = parseAmount(notification.gross_amount)
    if (
      typeof providerRef !== "string" ||
      typeof transactionId !== "string" ||
      typeof gatewayStatus !== "string" ||
      amount === null ||
      (notification.currency !== undefined && notification.currency !== "IDR")
    ) {
      return jsonResponse({ error: "Data transaksi notifikasi tidak lengkap atau tidak valid." }, 400)
    }

    let effectiveStatus = gatewayStatus
    if (gatewayStatus === "capture" && notification.fraud_status !== "accept") {
      effectiveStatus = notification.fraud_status === "deny" ? "deny" : "pending"
    }
    const supabaseUrl = Deno.env.get("SUPABASE_URL")
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
    if (!supabaseUrl || !serviceRoleKey) throw new Error("Konfigurasi service role Supabase belum lengkap.")

    const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    })
    if (gatewayStatus === "refund" || gatewayStatus === "partial_refund") {
      console.warn("Notifikasi refund Midtrans diterima; rekonsiliasi refund berada di luar alur pembayaran ini.")
      return jsonResponse({ status: "accepted_refund_for_manual_reconciliation" })
    }

    const supportedGatewayStatus = gatewayStatus === "failure" ? "deny" : effectiveStatus
    const { error } = await serviceClient.rpc("apply_midtrans_payment_notification", {
      p_provider_ref: providerRef,
      p_transaction_id: transactionId,
      p_amount: amount,
      p_gateway_status: supportedGatewayStatus,
      p_paid_at: parseMidtransTimestamp(notification.settlement_time ?? notification.transaction_time),
      p_raw_payload: notification,
    })
    if (error) {
      console.error("Notifikasi Midtrans ditolak oleh validasi database:", error.message)
      return jsonResponse({ error: "Data transaksi tidak cocok dengan pesanan." }, 400)
    }

    return jsonResponse({ status: "ok" })
  } catch (error) {
    console.error("Webhook Midtrans gagal diproses:", error)
    return jsonResponse({ error: "Notifikasi pembayaran belum dapat diproses." }, 500)
  }
})
