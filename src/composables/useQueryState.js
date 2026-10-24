import { useRoute, useRouter } from 'vue-router'

/** Menyimpan filter/halaman di URL (?q=...&page=2) agar refresh dan tombol back berfungsi. */
export function useQueryState() {
  const route = useRoute()
  const router = useRouter()
  const str = (k) => String(route.query[k] ?? '')
  const num = (k, d = 1) => Math.max(1, Number(route.query[k]) || d)
  function set(patch) {
    const next = { ...route.query, ...patch }
    for (const k of Object.keys(next)) {
      if (next[k] === '' || next[k] == null || (k === 'page' && Number(next[k]) === 1)) delete next[k]
    }
    router.push({ query: next })
  }
  return { route, str, num, set }
}
