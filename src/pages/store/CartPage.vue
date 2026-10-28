<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { RouterLink, useRouter } from 'vue-router'
import { useCartStore } from '@/stores/cart'
import { formatRupiah } from '@/lib/format'
import { FLAT_SHIPPING } from '@/lib/status'

const cart = useCartStore()
const router = useRouter()
const error = ref('')
const actionBusy = ref(false)
const selectedIds = ref([])
const knownIds = ref(new Set())

onMounted(() => cart.load().catch((e) => (error.value = e.message)))

watch(
  () => cart.items.map((item) => item.product_id),
  (productIds) => {
    const current = new Set(productIds)
    selectedIds.value = selectedIds.value.filter((id) => current.has(id))
    for (const id of productIds) {
      if (!knownIds.value.has(id)) selectedIds.value.push(id)
    }
    knownIds.value = current
  },
  { immediate: true },
)

async function run(fn) {
  if (actionBusy.value) return
  actionBusy.value = true
  error.value = ''
  try { await fn() } catch (e) { error.value = e.message }
  finally { actionBusy.value = false }
}

const imageOf = (p) => [...(p.product_images ?? [])].sort((a, b) => a.sort_order - b.sort_order)[0]?.url
const bermasalah = (item) => !item.products.is_active || item.products.stock < item.quantity
const selected = (item) => selectedIds.value.includes(item.product_id)
const groups = computed(() => {
  const grouped = new Map()
  for (const item of cart.items) {
    const id = item.products.umkm?.id ?? 'unknown'
    if (!grouped.has(id)) grouped.set(id, { id, name: item.products.umkm?.name || 'Toko PasarPintar', items: [] })
    grouped.get(id).items.push(item)
  }
  return [...grouped.values()]
})
const selectedItems = computed(() => cart.items.filter(selected))
const selectedCount = computed(() => selectedItems.value.reduce((count, item) => count + item.quantity, 0))
const selectedSubtotal = computed(() => selectedItems.value.reduce((sum, item) => sum + item.products.price * item.quantity, 0))
const selectedProblems = computed(() => selectedItems.value.filter(bermasalah))
const estimateShipping = computed(() => selectedItems.value.length ? FLAT_SHIPPING : 0)
const allSelected = computed(() => cart.items.length > 0 && selectedIds.value.length === cart.items.length)

function isGroupSelected(group) {
  return group.items.every(selected)
}

function toggleGroup(group, checked) {
  const groupIds = new Set(group.items.map((item) => item.product_id))
  selectedIds.value = checked
    ? [...new Set([...selectedIds.value, ...groupIds])]
    : selectedIds.value.filter((id) => !groupIds.has(id))
}

function toggleAll(checked) {
  selectedIds.value = checked ? cart.items.map((item) => item.product_id) : []
}

function checkout() {
  const ids = selectedItems.value.map((item) => item.product_id)
  if (ids.length && !selectedProblems.value.length && !actionBusy.value) {
    router.push({ name: 'checkout', query: { produk: ids.join(',') } })
  }
}
</script>

<template>
  <div class="mx-auto max-w-7xl px-4 pb-16 pt-8 md:px-6 lg:px-8">
    <div class="flex flex-wrap items-end justify-between gap-3">
      <div>
        <p class="text-sm font-medium text-indigo-700">Belanja praktis dari UMKM lokal</p>
        <h1 class="mt-1 text-3xl font-bold text-slate-900">Keranjang Belanja</h1>
      </div>
      <p v-if="cart.items.length" class="text-sm text-slate-500">{{ cart.items.length }} produk · {{ cart.count }} barang</p>
    </div>
    <p v-if="error || cart.error" class="mt-4 rounded-xl bg-bad-bg p-3 text-sm text-bad-fg" role="alert">{{ error || cart.error }}</p>

    <div v-if="cart.loading && !cart.items.length" class="mt-6 h-40 animate-pulse rounded-2xl bg-surface"></div>

    <div v-else-if="!cart.items.length" class="mt-6 rounded-2xl border border-slate-200 bg-white px-6 py-14 text-center shadow-sm sm:py-20">
      <div class="mx-auto flex h-28 w-28 items-center justify-center rounded-full border border-indigo-100 bg-indigo-50 text-indigo-700 shadow-sm ring-8 ring-indigo-50/60" aria-hidden="true">
        <svg viewBox="0 0 64 64" class="h-14 w-14" fill="none" stroke="currentColor" stroke-width="2.25" stroke-linecap="round" stroke-linejoin="round">
          <path d="M8 12h6l6 29h27l7-21H18" /><circle cx="25" cy="51" r="3" /><circle cx="45" cy="51" r="3" /><path d="M28 31h12M34 25v12" />
        </svg>
      </div>
      <h2 class="mt-6 text-xl font-bold text-slate-900">Keranjang Anda masih kosong</h2>
      <p class="mx-auto mt-2 max-w-sm text-sm leading-6 text-slate-500">Temukan produk pilihan dari mitra UMKM dan mulai isi keranjang Anda.</p>
      <RouterLink :to="{ name: 'katalog' }" class="btn bg-gray-900 text-white transition-colors hover:bg-black hover:shadow-md mt-6 inline-flex min-h-12 items-center justify-center rounded-xl px-7 font-semibold shadow-sm">Lihat katalog</RouterLink>
    </div>

    <div v-else class="mt-6 grid grid-cols-1 items-start gap-8 lg:grid-cols-3">
      <section class="space-y-4 lg:col-span-2">
        <div class="flex items-center gap-3 rounded-2xl border border-slate-200 bg-white px-4 py-3 shadow-sm">
          <input id="select-all-cart" type="checkbox" :checked="allSelected" class="h-4 w-4 rounded border-slate-300 text-gray-900 focus:ring-gray-900 accent-gray-900" @change="toggleAll($event.target.checked)" />
          <label for="select-all-cart" class="cursor-pointer text-sm font-medium text-slate-700">Pilih semua produk</label>
          <span class="ml-auto text-xs text-slate-500">{{ selectedIds.length }} dari {{ cart.items.length }} dipilih</span>
        </div>

        <section v-for="group in groups" :key="group.id" class="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm">
          <header class="flex items-center gap-3 border-b border-slate-100 bg-slate-50/70 px-4 py-3 sm:px-5">
            <input :id="`store-${group.id}`" type="checkbox" :checked="isGroupSelected(group)" class="h-4 w-4 rounded border-slate-300 text-gray-900 focus:ring-gray-900 accent-gray-900" @change="toggleGroup(group, $event.target.checked)" />
            <label :for="`store-${group.id}`" class="flex min-w-0 cursor-pointer items-center gap-2 text-sm font-semibold text-slate-900">
              <svg viewBox="0 0 24 24" class="h-4 w-4 shrink-0 text-indigo-700" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="M3 10h18l-1.5 11h-15L3 10Zm2-1 2-6h10l2 6M9 21v-7h6v7" /></svg>
              <span class="truncate">{{ group.name }}</span>
            </label>
            <span class="ml-auto text-xs text-slate-500">{{ group.items.length }} produk</span>
          </header>

          <ul class="divide-y divide-slate-100">
            <li v-for="item in group.items" :key="item.id" class="grid grid-cols-[20px_72px_minmax(0,1fr)] gap-3 px-4 py-4 sm:grid-cols-[20px_88px_minmax(0,1fr)_auto] sm:gap-4 sm:px-5">
              <input :id="`item-${item.id}`" type="checkbox" :checked="selected(item)" class="mt-1 h-4 w-4 rounded border-slate-300 text-gray-900 focus:ring-gray-900 accent-gray-900" :aria-label="`Pilih ${item.products.name}`" @change="selectedIds = $event.target.checked ? [...selectedIds, item.product_id] : selectedIds.filter((id) => id !== item.product_id)" />
              <RouterLink :to="{ name: 'produk', params: { slug: item.products.slug } }" class="h-[72px] w-[72px] overflow-hidden rounded-xl bg-slate-100 ring-1 ring-slate-200 sm:h-[88px] sm:w-[88px]">
                <img v-if="imageOf(item.products)" :src="imageOf(item.products)" :alt="item.products.name" class="h-full w-full object-cover" />
                <span v-else class="flex h-full items-center justify-center text-[10px] text-slate-400">Tanpa foto</span>
              </RouterLink>
              <div class="min-w-0">
                <RouterLink :to="{ name: 'produk', params: { slug: item.products.slug } }" class="line-clamp-2 text-sm font-semibold text-slate-900 hover:text-gray-900">{{ item.products.name }}</RouterLink>
                <p class="mt-1 text-sm font-bold text-gray-900">{{ formatRupiah(item.products.price) }}</p>
                <p v-if="bermasalah(item)" class="mt-1 text-xs font-medium text-bad-fg">
                  {{ item.products.is_active ? `Stok tersisa ${item.products.stock}. Kurangi jumlahnya.` : 'Produk tidak lagi dijual. Hapus dari keranjang.' }}
                </p>
                <div class="mt-3 flex items-center justify-between gap-2 sm:justify-start sm:gap-4">
                  <div class="flex items-center rounded-lg border border-slate-200" role="group" :aria-label="`Jumlah ${item.products.name}`">
                    <button class="h-8 w-8 rounded-md border border-gray-900 text-gray-900 transition hover:bg-gray-50 disabled:opacity-40" type="button" aria-label="Kurangi" :disabled="item.quantity <= 1 || cart.loading || actionBusy" @click="run(() => cart.setQty(item, item.quantity - 1))">−</button>
                    <span class="w-8 text-center text-xs font-semibold">{{ item.quantity }}</span>
                    <button class="h-8 w-8 rounded-md border border-gray-900 text-gray-900 transition hover:bg-gray-50 disabled:opacity-40" type="button" aria-label="Tambah" :disabled="item.quantity >= item.products.stock || cart.loading || actionBusy" @click="run(() => cart.setQty(item, item.quantity + 1))">+</button>
                  </div>
                  <button class="inline-flex items-center gap-1.5 rounded-lg border border-gray-900 px-2 py-1 text-xs font-medium text-gray-900 transition hover:bg-gray-50 disabled:opacity-50" type="button" :disabled="cart.loading || actionBusy" @click="run(() => cart.remove(item))">
                    <svg viewBox="0 0 20 20" class="h-4 w-4" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="M3.5 5.5h13m-11.5 0 .7 11h7.6l.7-11M8 5.5V3.7h4v1.8m-3 3v5m2-5v5" /></svg>
                    Hapus
                  </button>
                </div>
              </div>
              <p class="col-start-3 text-right text-sm font-bold text-gray-900 sm:col-start-auto">{{ formatRupiah(item.products.price * item.quantity) }}</p>
            </li>
          </ul>
        </section>
      </section>

      <aside class="h-fit rounded-2xl border border-slate-200 bg-white p-5 shadow-sm lg:sticky lg:top-24">
        <div class="flex items-center justify-between">
          <p class="text-base font-bold text-slate-900">Ringkasan Belanja</p>
          <svg viewBox="0 0 24 24" class="h-5 w-5 text-indigo-700" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="M4 4h2l2.2 10.5a2 2 0 0 0 2 1.5h7.5a2 2 0 0 0 1.9-1.4L21 9H7M10 20h.01M18 20h.01" /></svg>
        </div>
        <p class="mt-1 text-xs text-slate-500">Untuk {{ selectedCount }} barang terpilih</p>
        <dl class="mt-5 flex flex-col gap-3 text-sm">
          <div class="flex justify-between gap-3"><dt class="text-slate-500">Subtotal harga barang</dt><dd class="text-right font-bold text-gray-900">{{ formatRupiah(selectedSubtotal) }}</dd></div>
          <div class="flex justify-between gap-3"><dt class="text-slate-500">Estimasi ongkir</dt><dd class="text-right font-bold text-gray-900">{{ selectedItems.length ? formatRupiah(estimateShipping) : '—' }}</dd></div>
          <div class="flex justify-between gap-3 border-t border-slate-200 pt-3 text-base font-bold"><dt class="text-slate-900">Total sementara</dt><dd class="text-right font-bold text-gray-900">{{ formatRupiah(selectedSubtotal + estimateShipping) }}</dd></div>
        </dl>
        <button class="btn bg-gray-900 text-white transition-colors hover:bg-black hover:shadow-md mt-5 min-h-12 w-full rounded-xl font-semibold disabled:cursor-not-allowed disabled:opacity-50" type="button" :disabled="!selectedItems.length || selectedProblems.length > 0 || actionBusy" @click="checkout">Lanjut ke Checkout</button>
        <p v-if="!selectedItems.length" class="mt-3 text-center text-xs text-slate-500">Pilih produk yang ingin Anda checkout.</p>
        <p v-else-if="selectedProblems.length" class="mt-3 text-xs text-bad-fg">Perbaiki atau hapus item terpilih yang bertanda merah sebelum checkout.</p>
        <p class="mt-4 border-t border-slate-100 pt-3 text-xs leading-5 text-slate-500">Ongkir adalah perkiraan sementara dan akan ditampilkan kembali pada tahap checkout.</p>
      </aside>
    </div>
  </div>
</template>
