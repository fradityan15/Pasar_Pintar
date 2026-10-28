<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import ProductCard from '@/components/ProductCard.vue'
import { listCategories, listProducts } from '@/services/catalogService'
import { useCartStore } from '@/stores/cart'

const PAGE_SIZE = 12
const route = useRoute()
const router = useRouter()
const cart = useCartStore()

const categories = ref([])
const items = ref([])
const total = ref(0)
const loading = ref(true)
const error = ref('')
const search = ref(String(route.query.q ?? ''))
const addingProductId = ref('')
const toast = ref('')
const toastError = ref(false)
let requestId = 0
let toastTimeout

const q = computed(() => String(route.query.q ?? ''))
const slug = computed(() => String(route.query.kategori ?? ''))
const page = computed(() => Math.max(1, Number(route.query.page) || 1))
const totalPages = computed(() => Math.max(1, Math.ceil(total.value / PAGE_SIZE)))
const parents = computed(() => categories.value.filter((c) => !c.parent_id))

function setQuery(patch) {
  const next = { ...route.query, ...patch }
  for (const k of Object.keys(next)) if (!next[k] || (k === 'page' && next[k] === 1)) delete next[k]
  router.push({ name: 'katalog', query: next })
}

async function load() {
  const id = ++requestId
  loading.value = true
  error.value = ''
  try {
    const availableCategories = await listCategories()
    const selectedCategory = availableCategories.find((c) => c.slug === slug.value)
    const categoryIds = selectedCategory
      ? [selectedCategory.id, ...availableCategories.filter((c) => c.parent_id === selectedCategory.id).map((c) => c.id)]
      : null
    const res = await listProducts({ q: q.value, categoryIds, page: page.value, pageSize: PAGE_SIZE })
    if (id !== requestId) return
    categories.value = availableCategories
    items.value = res.items
    total.value = res.total
  } catch (e) {
    if (id === requestId) error.value = e.message
  } finally {
    if (id === requestId) loading.value = false
  }
}

watch(() => route.query, load, { immediate: true, deep: true })

onBeforeUnmount(() => clearTimeout(toastTimeout))

function showToast(message, isError = false) {
  clearTimeout(toastTimeout)
  toast.value = message
  toastError.value = isError
  toastTimeout = setTimeout(() => { toast.value = '' }, 4000)
}

async function addToCart(product) {
  addingProductId.value = product.id
  try {
    await cart.add(product, 1)
    showToast(`${product.name} ditambahkan ke keranjang.`)
  } catch (e) {
    showToast(`Produk gagal ditambahkan: ${e.message}`, true)
  } finally {
    addingProductId.value = ''
  }
}
</script>

<template>
  <div class="mx-auto max-w-7xl px-4 pb-16 pt-8 md:px-6 lg:px-8">
    <h1 class="text-3xl font-bold text-slate-900">Katalog</h1>

    <form class="mt-5 flex gap-3" role="search" @submit.prevent="setQuery({ q: search.trim(), page: 1 })">
      <label for="cari" class="sr-only">Cari produk</label>
      <input id="cari" v-model="search" class="input max-w-md" type="search" placeholder="Cari nama produk" />
      <button class="btn min-h-[44px] rounded-xl bg-gray-900 px-5 text-sm font-semibold text-white transition-colors hover:bg-black hover:shadow-md" type="submit">Cari</button>
    </form>

    <div class="mt-4 flex flex-wrap gap-2" role="group" aria-label="Filter kategori">
      <button
        type="button"
        class="rounded-full border px-4 py-2 text-sm font-medium transition-colors"
        :class="!slug ? 'border-gray-900 bg-gray-900 text-white' : 'border-slate-200 bg-white text-slate-700 hover:bg-slate-100'"
        :aria-pressed="!slug"
        @click="setQuery({ kategori: '', page: 1 })"
      >Semua</button>
      <button
        v-for="c in parents"
        :key="c.id"
        type="button"
        class="rounded-full border px-4 py-2 text-sm font-medium transition-colors"
        :class="slug === c.slug ? 'border-gray-900 bg-gray-900 text-white' : 'border-slate-200 bg-white text-slate-700 hover:bg-slate-100'"
        :aria-pressed="slug === c.slug"
        @click="setQuery({ kategori: c.slug, page: 1 })"
      >{{ c.name }}</button>
    </div>

    <p v-if="error" class="mt-6 rounded-xl bg-bad-bg p-4 text-sm text-bad-fg" role="alert">
      Produk belum bisa dimuat: {{ error }}
      <button class="ml-2 font-semibold underline" type="button" @click="load">Coba lagi</button>
    </p>
    <div v-else-if="loading" class="mt-6 grid grid-cols-2 gap-3 sm:gap-4 md:grid-cols-3 lg:grid-cols-5" aria-label="Memuat produk" aria-busy="true">
      <div v-for="n in 8" :key="n" class="animate-pulse">
        <div class="aspect-square rounded-[14px] bg-slate-200"></div>
        <div class="mt-3 h-4 w-4/5 rounded bg-slate-200"></div>
        <div class="mt-2 h-3 w-2/3 rounded bg-slate-200"></div>
        <div class="mt-3 h-4 w-1/2 rounded bg-slate-200"></div>
      </div>
    </div>
    <div v-else-if="!items.length" class="mt-6 rounded-xl bg-surface p-8 text-center">
      <p class="font-semibold">Produk tidak ditemukan</p>
      <p class="mt-1 text-sm text-muted">Coba kata kunci lain atau pilih kategori yang berbeda.</p>
    </div>
    <template v-else>
      <p class="mt-6 text-sm text-muted">{{ total }} produk</p>
      <div class="mt-3 grid grid-cols-2 gap-3 sm:gap-4 md:grid-cols-3 lg:grid-cols-5">
        <ProductCard v-for="p in items" :key="p.id" :product="p" :adding="addingProductId === p.id" @add="addToCart" />
      </div>
      <nav v-if="totalPages > 1" class="mt-8 flex items-center justify-center gap-4 text-sm" aria-label="Halaman">
        <button class="btn-outline" type="button" :disabled="page <= 1" @click="setQuery({ page: page - 1 })">Sebelumnya</button>
        <span>Halaman {{ page }} dari {{ totalPages }}</span>
        <button class="btn-outline" type="button" :disabled="page >= totalPages" @click="setQuery({ page: page + 1 })">Berikutnya</button>
      </nav>
    </template>

    <Teleport to="body">
      <Transition
        enter-active-class="transition duration-200 ease-out"
        enter-from-class="translate-y-2 opacity-0"
        enter-to-class="translate-y-0 opacity-100"
        leave-active-class="transition duration-150 ease-in"
        leave-from-class="translate-y-0 opacity-100"
        leave-to-class="translate-y-2 opacity-0"
      >
        <p
          v-if="toast"
          class="fixed right-4 top-4 z-50 max-w-sm rounded-xl border p-4 text-sm shadow-lg sm:right-6 sm:top-6"
          :class="toastError ? 'border-red-200 bg-white text-red-800' : 'border-indigo-200 bg-white text-indigo-800'"
          role="status"
          aria-live="polite"
        >{{ toast }}</p>
      </Transition>
    </Teleport>
  </div>
</template>
