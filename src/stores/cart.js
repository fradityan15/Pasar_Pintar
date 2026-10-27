import { defineStore } from 'pinia'
import { computed, ref, watch } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { deleteCartItem, fetchCart, updateCartQuantity, upsertCartItem } from '@/services/cartService'

const GUEST_CART_KEY = 'pasarpintar:guest-cart'

function readGuestCart() {
  const raw = window.localStorage.getItem(GUEST_CART_KEY)
  if (!raw) return []
  const value = JSON.parse(raw)
  if (!Array.isArray(value)) throw new Error('Data keranjang lokal tidak valid.')
  return value
}

function saveGuestCart(items) {
  if (items.length) window.localStorage.setItem(GUEST_CART_KEY, JSON.stringify(items))
  else window.localStorage.removeItem(GUEST_CART_KEY)
}

export const useCartStore = defineStore('cart', () => {
  const auth = useAuthStore()
  const items = ref([])
  const loading = ref(false)
  const error = ref('')
  let loadPromise = null

  const count = computed(() => items.value.reduce((n, i) => n + i.quantity, 0))
  const subtotal = computed(() => items.value.reduce((s, i) => s + i.products.price * i.quantity, 0))
  // Item yang tidak bisa di-checkout (dinonaktifkan atau stok kurang).
  const problems = computed(() =>
    items.value.filter((i) => !i.products.is_active || i.products.stock < i.quantity),
  )

  async function load() {
    if (loadPromise) return loadPromise
    loadPromise = loadCart()
    try {
      await loadPromise
    } finally {
      loadPromise = null
    }
  }

  async function loadCart() {
    error.value = ''
    if (!auth.user) {
      items.value = readGuestCart()
      return
    }

    loading.value = true
    try {
      let remoteItems = await fetchCart()
      const guestItems = readGuestCart()
      let remainingGuestItems = [...guestItems]

      for (const guestItem of guestItems) {
        const remoteItem = remoteItems.find((item) => item.product_id === guestItem.product_id)
        const quantity = (remoteItem?.quantity ?? 0) + guestItem.quantity
        if (quantity > guestItem.products.stock) {
          throw new Error(`Stok ${guestItem.products.name} hanya tersisa ${guestItem.products.stock}. Sesuaikan jumlah sebelum melanjutkan.`)
        }
        await upsertCartItem(auth.user.id, guestItem.product_id, quantity)
        remainingGuestItems = remainingGuestItems.filter((item) => item.product_id !== guestItem.product_id)
        saveGuestCart(remainingGuestItems)
        remoteItems = remoteItem
          ? remoteItems.map((item) => item.product_id === guestItem.product_id ? { ...item, quantity } : item)
          : [...remoteItems, guestItem]
      }

      items.value = await fetchCart()
    } catch (e) {
      error.value = e.message
      throw e
    } finally {
      loading.value = false
    }
  }

  async function add(product, qty) {
    const existing = items.value.find((i) => i.product_id === product.id)?.quantity ?? 0
    const next = existing + qty
    if (next > product.stock) throw new Error(`Stok hanya tersisa ${product.stock}.`)
    if (!auth.user) {
      const existingItem = items.value.find((item) => item.product_id === product.id)
      const nextItems = existingItem
        ? items.value.map((item) => item.product_id === product.id ? { ...item, quantity: next } : item)
        : [...items.value, { id: `guest-${product.id}`, product_id: product.id, quantity: qty, products: product }]
      saveGuestCart(nextItems)
      items.value = nextItems
      return
    }
    await upsertCartItem(auth.user.id, product.id, next)
    await load()
  }

  async function setQty(item, qty) {
    const q = Math.max(1, Math.min(qty, item.products.stock || 1))
    if (!auth.user) {
      const nextItems = items.value.map((row) => row.id === item.id ? { ...row, quantity: q } : row)
      saveGuestCart(nextItems)
      items.value = nextItems
      return
    }
    await updateCartQuantity(item.id, q)
    await load()
  }

  async function remove(item) {
    if (!auth.user) {
      const nextItems = items.value.filter((row) => row.id !== item.id)
      saveGuestCart(nextItems)
      items.value = nextItems
      return
    }
    await deleteCartItem(item.id)
    await load()
  }

  watch(() => auth.user?.id, () => {
    load().catch((e) => { error.value = e.message })
  }, { immediate: true })

  return { items, loading, error, count, subtotal, problems, load, add, setQty, remove }
})
