export const MIDTRANS_API = "https://api.sandbox.midtrans.com/v2"

export function getServerKey(): string {
  const key = Deno.env.get("MIDTRANS_SERVER_KEY")
  if (!key) throw new Error("MIDTRANS_SERVER_KEY belum dikonfigurasi.")
  return key
}

export function authorizationHeader(serverKey: string): string {
  return `Basic ${btoa(`${serverKey}:`)}`
}

export function parseAmount(value: unknown): number | null {
  if (typeof value !== "string" && typeof value !== "number") return null
  const text = String(value)
  if (!/^\d+(?:\.0{1,2})?$/.test(text)) return null
  const amount = Number(text)
  return Number.isSafeInteger(amount) && amount > 0 ? amount : null
}

export async function verifyNotificationSignature(
  notification: Record<string, unknown>,
  serverKey: string,
): Promise<boolean> {
  const orderId = notification.order_id
  const statusCode = notification.status_code
  const grossAmount = notification.gross_amount
  const providedSignature = notification.signature_key
  if (
    typeof orderId !== "string" ||
    typeof statusCode !== "string" ||
    typeof grossAmount !== "string" ||
    typeof providedSignature !== "string" ||
    !/^[a-f\d]{128}$/i.test(providedSignature)
  ) return false

  const message = `${orderId}${statusCode}${grossAmount}${serverKey}`
  const digest = await crypto.subtle.digest("SHA-512", new TextEncoder().encode(message))
  const expected = [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("")
  return constantTimeEqual(expected, providedSignature.toLowerCase())
}

function constantTimeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false
  let difference = 0
  for (let index = 0; index < left.length; index += 1) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index)
  }
  return difference === 0
}

export function parseMidtransTimestamp(value: unknown): string | null {
  if (typeof value !== "string") return null
  let normalized = value.includes("T") ? value : value.replace(" ", "T")
  const compactOffset = normalized.match(/([+-]\d{2})(\d{2})$/)
  if (compactOffset) {
    normalized = `${normalized.slice(0, -5)}${compactOffset[1]}:${compactOffset[2]}`
  }
  const withJakartaOffset = /(?:Z|[+-]\d{2}:\d{2})$/i.test(normalized)
    ? normalized
    : `${normalized}+07:00`
  const parsed = new Date(withJakartaOffset)
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString()
}

export function safeQrUrl(value: unknown): string | null {
  if (typeof value !== "string") return null
  try {
    const url = new URL(value)
    if (url.protocol !== "https:" || !url.hostname.endsWith(".midtrans.com")) return null
    return url.toString()
  } catch {
    return null
  }
}
