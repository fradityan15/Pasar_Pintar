import { defineStore } from 'pinia'
import { computed, ref, watch } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { deleteCartItem, fetchCart, updateCartQuantity, upsertCartItem } from '@/services/cartService'

export const useCartStore = defineStore('cart', () => {
  const auth = useAuthStore()
  const items = ref([])
  const loading = ref(false)

  const count = computed(() => items.value.reduce((n, i) => n + i.quantity, 0))
  const subtotal = computed(() => items.value.reduce((s, i) => s + i.products.price * i.quantity, 0))
  // Item yang tidak bisa di-checkout (dinonaktifkan atau stok kurang).
  const problems = computed(() =>
    items.value.filter((i) => !i.products.is_active || i.products.stock < i.quantity),
  )

  async function load() {
    if (!auth.user) { items.value = []; return }
    loading.value = true
    try { items.value = await fetchCart() } finally { loading.value = false }
  }

  async function add(product, qty) {
    const existing = items.value.find((i) => i.product_id === product.id)?.quantity ?? 0
    const next = existing + qty
    if (next > product.stock) throw new Error(`Stok hanya tersisa ${product.stock}.`)
    await upsertCartItem(auth.user.id, product.id, next)
    await load()
  }

  async function setQty(item, qty) {
    const q = Math.max(1, Math.min(qty, item.products.stock || 1))
    await updateCartQuantity(item.id, q)
    await load()
  }

  async function remove(item) {
    await deleteCartItem(item.id)
    await load()
  }

  watch(() => auth.user?.id, load, { immediate: true })

  return { items, loading, count, subtotal, problems, load, add, setQty, remove }
})
