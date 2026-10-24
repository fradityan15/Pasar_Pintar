<script setup>
import { computed, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import ProductCard from '@/components/ProductCard.vue'
import { listCategories, listProducts } from '@/services/catalogService'

const PAGE_SIZE = 12
const route = useRoute()
const router = useRouter()

const categories = ref([])
const items = ref([])
const total = ref(0)
const loading = ref(true)
const error = ref('')
const search = ref(String(route.query.q ?? ''))
let requestId = 0

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
</script>

<template>
  <div class="mx-auto max-w-7xl px-4 pb-16 pt-8 sm:px-10">
    <h1 class="text-3xl font-bold">Katalog</h1>

    <form class="mt-5 flex gap-3" role="search" @submit.prevent="setQuery({ q: search.trim(), page: 1 })">
      <label for="cari" class="sr-only">Cari produk</label>
      <input id="cari" v-model="search" class="input max-w-md" type="search" placeholder="Cari nama produk" />
      <button class="btn-primary" type="submit">Cari</button>
    </form>

    <div class="mt-4 flex flex-wrap gap-2" role="group" aria-label="Filter kategori">
      <button
        type="button"
        class="rounded-full border px-4 py-2 text-sm font-medium"
        :class="!slug ? 'border-ink bg-ink text-white' : 'border-line hover:bg-surface'"
        :aria-pressed="!slug"
        @click="setQuery({ kategori: '', page: 1 })"
      >Semua</button>
      <button
        v-for="c in parents"
        :key="c.id"
        type="button"
        class="rounded-full border px-4 py-2 text-sm font-medium"
        :class="slug === c.slug ? 'border-ink bg-ink text-white' : 'border-line hover:bg-surface'"
        :aria-pressed="slug === c.slug"
        @click="setQuery({ kategori: c.slug, page: 1 })"
      >{{ c.name }}</button>
    </div>

    <p v-if="error" class="mt-6 rounded-xl bg-bad-bg p-4 text-sm text-bad-fg" role="alert">
      Produk belum bisa dimuat: {{ error }}
      <button class="ml-2 font-semibold underline" type="button" @click="load">Coba lagi</button>
    </p>
    <div v-else-if="loading" class="mt-6 grid grid-cols-2 gap-4 md:grid-cols-4">
      <div v-for="n in 8" :key="n" class="aspect-square animate-pulse rounded-[14px] bg-surface"></div>
    </div>
    <div v-else-if="!items.length" class="mt-6 rounded-xl bg-surface p-8 text-center">
      <p class="font-semibold">Produk tidak ditemukan</p>
      <p class="mt-1 text-sm text-muted">Coba kata kunci lain atau pilih kategori yang berbeda.</p>
    </div>
    <template v-else>
      <p class="mt-6 text-sm text-muted">{{ total }} produk</p>
      <div class="mt-3 grid grid-cols-2 gap-4 md:grid-cols-4">
        <ProductCard v-for="p in items" :key="p.id" :product="p" />
      </div>
      <nav v-if="totalPages > 1" class="mt-8 flex items-center justify-center gap-4 text-sm" aria-label="Halaman">
        <button class="btn-outline" type="button" :disabled="page <= 1" @click="setQuery({ page: page - 1 })">Sebelumnya</button>
        <span>Halaman {{ page }} dari {{ totalPages }}</span>
        <button class="btn-outline" type="button" :disabled="page >= totalPages" @click="setQuery({ page: page + 1 })">Berikutnya</button>
      </nav>
    </template>
  </div>
</template>
