<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { RouterLink, useRoute, useRouter } from 'vue-router'
import { getProductBySlug } from '@/services/catalogService'
import { listProductReviews } from '@/services/productReviewService'
import { useAuthStore } from '@/stores/auth'
import { useCartStore } from '@/stores/cart'
import { formatRupiah, formatTanggal } from '@/lib/format'

const route = useRoute()
const router = useRouter()
const auth = useAuthStore()
const cart = useCartStore()

const product = ref(null)
const loading = ref(true)
const error = ref('')
const qty = ref(1)
const active = ref(0)
const adding = ref(false)
const added = ref(false)
const addError = ref('')
const reviews = ref([])
const reviewsLoading = ref(false)
const reviewsError = ref('')
let productRequestId = 0
let toastTimeout

const images = computed(() =>
  [...(product.value?.product_images ?? [])].sort((a, b) => a.sort_order - b.sort_order),
)
const origin = computed(() =>
  [product.value?.umkm?.regions?.name, product.value?.umkm?.regions?.province].filter(Boolean).join(', '),
)
const averageRating = computed(() =>
  reviews.value.length
    ? reviews.value.reduce((total, review) => total + review.rating, 0) / reviews.value.length
    : 0,
)

async function loadReviews(productId = product.value?.id) {
  if (!productId) return
  const requestId = productRequestId
  reviewsLoading.value = true
  reviewsError.value = ''
  try {
    const result = await listProductReviews(productId)
    if (requestId === productRequestId) reviews.value = result
  } catch (e) {
    if (requestId === productRequestId) reviewsError.value = e.message
  } finally {
    if (requestId === productRequestId) reviewsLoading.value = false
  }
}

async function load() {
  const requestId = ++productRequestId
  loading.value = true
  error.value = ''
  product.value = null
  reviews.value = []
  reviewsError.value = ''
  try {
    const loadedProduct = await getProductBySlug(route.params.slug)
    if (requestId !== productRequestId) return
    product.value = loadedProduct
    qty.value = 1
    active.value = 0
    added.value = false
    addError.value = ''
    if (loadedProduct) await loadReviews(loadedProduct.id)
  } catch (e) {
    if (requestId === productRequestId) error.value = e.message
  } finally {
    if (requestId === productRequestId) loading.value = false
  }
}
watch(() => route.params.slug, load, { immediate: true })
onBeforeUnmount(() => clearTimeout(toastTimeout))

function ubahQty(delta) {
  qty.value = Math.max(1, Math.min(product.value.stock, qty.value + delta))
}

async function tambah() {
  adding.value = true
  addError.value = ''
  added.value = false
  clearTimeout(toastTimeout)
  try {
    await cart.add(product.value, qty.value)
    added.value = true
    toastTimeout = setTimeout(() => { added.value = false }, 5000)
  } catch (e) {
    addError.value = e.message
  } finally {
    adding.value = false
  }
}

async function beliSekarang() {
  if (!auth.isLoggedIn) return router.push({ name: 'login', query: { redirect: route.fullPath } })
  adding.value = true
  addError.value = ''
  try {
    await cart.add(product.value, qty.value)
    await router.push({ name: 'checkout' })
  } catch (e) {
    addError.value = e.message
  } finally {
    adding.value = false
  }
}
</script>

<template>
  <div class="mx-auto max-w-7xl px-4 pb-16 pt-6 md:px-6 lg:px-8">
    <RouterLink :to="{ name: 'katalog' }" class="text-sm font-medium text-muted">← Kembali ke katalog</RouterLink>

    <Teleport to="body">
      <Transition
        enter-active-class="transition duration-200 ease-out"
        enter-from-class="translate-y-2 opacity-0"
        enter-to-class="translate-y-0 opacity-100"
        leave-active-class="transition duration-150 ease-in"
        leave-from-class="translate-y-0 opacity-100"
        leave-to-class="translate-y-2 opacity-0"
      >
        <div v-if="added" class="fixed right-4 top-4 z-50 flex max-w-sm items-start gap-3 rounded-xl border border-indigo-200 bg-white p-4 shadow-lg sm:right-6 sm:top-6" role="status" aria-live="polite">
          <span class="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-indigo-50 text-indigo-700" aria-hidden="true">
            <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="m5 12 4 4L19 6" /></svg>
          </span>
          <div class="min-w-0 flex-1">
            <p class="text-sm font-semibold text-slate-900">Ditambahkan ke keranjang</p>
            <RouterLink :to="{ name: 'keranjang' }" class="mt-1 inline-block text-sm font-medium text-gray-900 underline underline-offset-2">Lihat keranjang</RouterLink>
          </div>
          <button class="rounded p-1 text-slate-400 transition hover:bg-slate-100 hover:text-slate-700" type="button" aria-label="Tutup notifikasi" @click="added = false">
            <svg viewBox="0 0 20 20" class="h-4 w-4" fill="currentColor" aria-hidden="true"><path d="M4.293 4.293a1 1 0 0 1 1.414 0L10 8.586l4.293-4.293a1 1 0 1 1 1.414 1.414L11.414 10l4.293 4.293a1 1 0 0 1-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 0 1-1.414-1.414L8.586 10 4.293 5.707a1 1 0 0 1 0-1.414Z" /></svg>
          </button>
        </div>
      </Transition>
    </Teleport>

    <div v-if="loading" class="mt-6 grid gap-8 md:grid-cols-2">
      <div class="aspect-square animate-pulse rounded-2xl bg-surface"></div>
      <div class="h-64 animate-pulse rounded-2xl bg-surface"></div>
    </div>
    <p v-else-if="error" class="mt-6 rounded-xl bg-bad-bg p-4 text-sm text-bad-fg" role="alert">
      Produk belum bisa dimuat: {{ error }}
      <button class="ml-2 font-semibold underline" type="button" @click="load">Coba lagi</button>
    </p>
    <div v-else-if="!product" class="mt-6 rounded-xl bg-surface p-8 text-center">
      <p class="font-semibold">Produk tidak ditemukan</p>
      <p class="mt-1 text-sm text-muted">Produk mungkin sudah tidak dijual.</p>
      <RouterLink :to="{ name: 'katalog' }" class="btn bg-gray-900 text-white transition-colors hover:bg-black hover:shadow-md mt-4">Lihat katalog</RouterLink>
    </div>

    <template v-else-if="product">
      <div class="mt-6 grid grid-cols-1 items-start gap-8 md:grid-cols-2">
        <div class="min-w-0">
        <div class="aspect-square overflow-hidden rounded-2xl bg-white p-3 shadow-sm ring-1 ring-slate-200 sm:p-5">
          <img v-if="images[active]" :src="images[active].url" :alt="product.name" class="h-full w-full object-cover" />
          <div v-else class="flex h-full items-center justify-center rounded-xl bg-slate-50 text-sm text-slate-400">Foto produk belum tersedia</div>
          </div>
        <div v-if="images.length > 1" class="mt-3 flex gap-2">
          <button
            v-for="(img, i) in images"
            :key="img.url"
            type="button"
            class="h-16 w-16 overflow-hidden rounded-xl border-2 bg-white transition sm:h-20 sm:w-20"
            :class="i === active ? 'border-gray-900' : 'border-slate-200 hover:border-slate-400'"
            :aria-label="`Foto ${i + 1}`"
            @click="active = i"
          ><img :src="img.url" alt="" class="h-full w-full object-cover" /></button>
        </div>
      </div>

        <div class="flex min-w-0 flex-col gap-5 md:py-2">
        <div>
          <p v-if="product.categories?.name" class="text-sm font-medium text-indigo-700">{{ product.categories.name }}</p>
          <h1 class="mt-2 text-2xl font-bold leading-tight text-slate-900 sm:text-3xl">{{ product.name }}</h1>
        </div>

        <div class="border-y border-slate-200 py-4">
          <p class="text-3xl font-bold tracking-tight text-gray-900 sm:text-4xl">{{ formatRupiah(product.price) }}</p>
          <p v-if="product.stock > 0" class="mt-1 text-sm text-slate-500">Stok tersedia: {{ product.stock }}</p>
          <p v-else class="mt-1 text-sm font-medium text-red-600">Stok produk ini sedang habis</p>
        </div>

        <section v-if="product.umkm" class="rounded-xl border border-slate-200 bg-white p-4">
          <div class="flex items-center gap-3">
            <div class="flex h-12 w-12 shrink-0 items-center justify-center overflow-hidden rounded-full bg-indigo-50 text-sm font-bold text-indigo-800 ring-1 ring-indigo-100">
              <img v-if="product.umkm.logo_url" :src="product.umkm.logo_url" :alt="`Logo ${product.umkm.name}`" class="h-full w-full object-cover" />
              <span v-else>{{ product.umkm.name?.slice(0, 1)?.toUpperCase() || 'T' }}</span>
            </div>
            <div class="min-w-0 flex-1">
              <div class="flex flex-wrap items-center gap-1.5">
                <RouterLink
                  v-if="product.umkm.slug"
                  :to="{ name: 'umkm-detail', params: { slug: product.umkm.slug } }"
                  class="truncate text-sm font-semibold text-slate-900 hover:text-gray-900"
                >{{ product.umkm.name }}</RouterLink>
                <p v-else class="truncate text-sm font-semibold text-slate-900">{{ product.umkm.name }}</p>
                <span v-if="product.umkm.is_verified" class="inline-flex items-center gap-1 rounded-full bg-indigo-50 px-2 py-0.5 text-[10px] font-semibold text-indigo-700">
                  <svg viewBox="0 0 20 20" class="h-3 w-3" fill="currentColor" aria-hidden="true"><path fill-rule="evenodd" d="M10 1.667 12.575 3l2.9.2.2 2.9L17 8.667l-1.325 2.575-.2 2.9-2.9.2L10 15.667l-2.575-1.325-2.9-.2-.2-2.9L3 8.667 4.325 6.1l.2-2.9 2.9-.2L10 1.667Zm3.04 5.9a.833.833 0 0 0-1.18-1.18L9.167 9.08 8.14 8.053a.833.833 0 0 0-1.18 1.18l1.62 1.62a.833.833 0 0 0 1.18 0l3.28-3.286Z" clip-rule="evenodd" /></svg>
                  Terverifikasi
                </span>
              </div>
              <p class="mt-1 truncate text-xs text-slate-500">{{ origin || 'Mitra UMKM PasarPintar' }}</p>
            </div>
          </div>
          <RouterLink
            v-if="product.umkm.slug"
            :to="{ name: 'umkm-detail', params: { slug: product.umkm.slug } }"
            class="mt-3 inline-flex min-h-9 w-full items-center justify-center rounded-lg border border-gray-900 px-3 text-xs font-semibold text-gray-900 transition hover:bg-gray-50"
          >Kunjungi Toko</RouterLink>
        </section>

        <p v-if="product.description" class="max-w-prose whitespace-pre-line text-sm leading-6 text-slate-600">{{ product.description }}</p>

        <dl class="grid max-w-xs grid-cols-2 gap-y-2 text-sm">
          <dt class="text-slate-500">Berat</dt><dd class="text-right font-medium text-slate-800">{{ product.weight_gram ? `${product.weight_gram} g` : '—' }}</dd>
          <dt class="text-slate-500">Ketersediaan</dt><dd class="text-right font-medium" :class="product.stock > 0 ? 'text-indigo-700' : 'text-red-600'">{{ product.stock > 0 ? 'Tersedia' : 'Habis' }}</dd>
        </dl>

        <div v-if="product.stock > 0" class="mt-1 space-y-3 border-t border-slate-200 pt-5">
          <div class="flex flex-wrap items-center gap-3">
            <span class="text-sm font-medium text-slate-700">Jumlah</span>
            <div class="flex items-center rounded-lg border border-slate-200" role="group" aria-label="Jumlah">
              <button class="h-10 w-10 rounded-md border border-gray-900 text-lg text-gray-900 transition hover:bg-gray-50 disabled:opacity-40" type="button" aria-label="Kurangi" :disabled="qty <= 1 || adding" @click="ubahQty(-1)">−</button>
              <span class="w-10 text-center text-sm font-semibold text-slate-900" aria-live="polite">{{ qty }}</span>
              <button class="h-10 w-10 rounded-md border border-gray-900 text-lg text-gray-900 transition hover:bg-gray-50 disabled:opacity-40" type="button" aria-label="Tambah" :disabled="qty >= product.stock || adding" @click="ubahQty(1)">+</button>
            </div>
          </div>
          <div class="grid gap-3 sm:grid-cols-2">
            <button class="btn bg-gray-900 text-white transition-colors hover:bg-black hover:shadow-md min-h-[52px] px-5 text-sm font-semibold disabled:opacity-60" type="button" :disabled="adding" @click="tambah">
              {{ adding ? 'Memproses…' : 'Tambah ke keranjang' }}
            </button>
            <button class="min-h-[52px] rounded-xl border border-gray-900 px-5 text-sm font-semibold text-gray-900 transition hover:bg-gray-50 disabled:opacity-60" type="button" :disabled="adding" @click="beliSekarang">
              Beli Sekarang
            </button>
        </div>
        </div>
        <p v-else class="rounded-xl bg-red-50 p-3 text-sm text-red-700">Produk ini belum dapat dipesan karena stok sedang habis.</p>

        <p v-if="addError" class="rounded-xl bg-bad-bg p-3 text-sm text-bad-fg" role="alert">{{ addError }}</p>
        </div>
      </div>

      <section class="mt-10 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm md:p-6 lg:p-8" aria-labelledby="reviews-heading">
        <div class="flex flex-wrap items-center justify-between gap-4 border-b border-slate-100 pb-5">
          <div>
            <h2 id="reviews-heading" class="text-xl font-bold text-slate-900">Ulasan Pembeli</h2>
            <p class="mt-1 text-sm text-slate-500">{{ reviews.length }} ulasan</p>
          </div>
          <div v-if="reviews.length" class="flex items-center gap-2" aria-label="Rating rata-rata">
            <div class="flex text-xl" aria-hidden="true">
              <span v-for="star in 5" :key="star" :class="star <= averageRating ? 'text-gray-900' : 'text-slate-300'">★</span>
            </div>
            <span class="text-lg font-bold text-slate-900">{{ averageRating.toFixed(1) }}</span>
          </div>
        </div>

        <p v-if="reviewsError" class="mt-4 rounded-xl bg-bad-bg p-4 text-sm text-bad-fg" role="alert">
          Ulasan belum bisa dimuat: {{ reviewsError }}
          <button class="ml-2 font-semibold underline" type="button" @click="loadReviews()">Coba lagi</button>
        </p>
        <div v-else-if="reviewsLoading" class="mt-5 h-24 animate-pulse rounded-xl bg-surface"></div>
        <p v-else-if="!reviews.length" class="mt-5 rounded-xl bg-surface p-6 text-center text-sm text-muted">
          Belum ada ulasan untuk produk ini.
        </p>
        <ul v-else class="divide-y divide-slate-100">
          <li v-for="review in reviews" :key="review.id" class="py-5 first:pt-5 last:pb-0">
            <div class="flex flex-wrap items-center justify-between gap-2">
              <div class="flex items-center gap-2">
                <span class="font-medium text-slate-800">Pembeli</span>
                <span class="flex text-sm" :aria-label="`Rating ${review.rating} dari 5`">
                  <span v-for="star in 5" :key="star" :class="star <= review.rating ? 'text-gray-900' : 'text-slate-300'" aria-hidden="true">★</span>
                </span>
              </div>
              <time class="text-xs text-slate-500" :datetime="review.created_at">{{ formatTanggal(review.created_at) }}</time>
            </div>
            <p v-if="review.comment" class="mt-2 whitespace-pre-line text-sm leading-6 text-slate-600">{{ review.comment }}</p>
          </li>
        </ul>
      </section>
    </template>
  </div>
</template>
