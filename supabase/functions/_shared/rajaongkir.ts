export const RAJAONGKIR_API = "https://rajaongkir.komerce.id/api/v1"

function getApiKey(): string {
  const apiKey = Deno.env.get("RAJAONGKIR_API_KEY")?.trim()
  if (!apiKey) throw new Error("RAJAONGKIR_API_KEY belum dikonfigurasi.")
  return apiKey
}

export async function rajaongkirRequest(path: string, init: RequestInit = {}): Promise<Response> {
  const headers = new Headers(init.headers)
  headers.set("key", getApiKey())
  headers.set("Accept", "application/json")
  return fetch(`${RAJAONGKIR_API}${path}`, {
    ...init,
    headers,
    signal: AbortSignal.timeout(15000),
  })
}

export function courierCodes(values: unknown): string[] {
  const aliases: Record<string, string> = {
    jne: "jne",
    "j&t express": "jnt",
    jnt: "jnt",
    "pos indonesia": "pos",
    pos: "pos",
    tiki: "tiki",
    sicepat: "sicepat",
    anteraja: "anteraja",
    ninja: "ninja",
    idexpress: "ide",
  }
  if (!Array.isArray(values)) return ["jne", "jnt", "sicepat", "pos", "tiki", "anteraja"]
  const codes = values
    .map((value) => typeof value === "string" ? aliases[value.trim().toLowerCase()] : null)
    .filter((value): value is string => Boolean(value))
  return [...new Set(codes)]
}
