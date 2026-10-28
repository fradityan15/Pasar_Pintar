<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { RouterLink } from 'vue-router'
import ProductCard from '@/components/ProductCard.vue'
import { listCategories, listFeatured } from '@/services/catalogService'

const categories = ref([])
const products = ref([])
const featuredProducts = ref([])
const currentIndex = ref(0)
const loading = ref(true)
const error = ref('')
const heroProduct = computed(() => featuredProducts.value[currentIndex.value] ?? null)
let autoplay

async function load() {
  loading.value = true
  error.value = ''
  try {
    const [cats, items] = await Promise.all([listCategories(), listFeatured(8)])
    categories.value = cats.filter((c) => !c.parent_id)
    products.value = items
    featuredProducts.value = items.map((product) => ({
      id: product.id,
      slug: product.slug,
      image_url: [...(product.product_images ?? [])].sort((a, b) => a.sort_order - b.sort_order)[0]?.url,
      product_name: product.name,
      umkm_name: [product.umkm?.name, product.umkm?.regions?.name].filter(Boolean).join(' · '),
    }))
    currentIndex.value = 0
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

function pilihSlide(index) {
  currentIndex.value = index
}

onMounted(() => {
  load()
  autoplay = window.setInterval(() => {
    if (featuredProducts.value.length > 1) {
      currentIndex.value = (currentIndex.value + 1) % featuredProducts.value.length
    }
  }, 5000)
})

onUnmounted(() => window.clearInterval(autoplay))
</script>

<template>
  <div class="mx-auto max-w-7xl px-4 pb-16 md:px-6 lg:px-8">
    <section class="mt-2 grid items-center gap-8 overflow-hidden rounded-2xl bg-surface p-6 sm:p-10 md:grid-cols-2 md:gap-12 md:p-14">
      <div class="flex flex-col items-start gap-5">
        <span class="rounded-full bg-white px-3 py-1 text-xs font-semibold text-gold-dark">Cerita dan produk lokal Indonesia</span>
        <h1 class="text-4xl font-bold leading-[1.08] tracking-tight sm:text-5xl">
          Cita rasa dan karya khas daerah, langsung dari UMKM.
        </h1>
        <p class="max-w-md text-[17px] leading-normal text-[#4B5563]">
          Temukan makanan, kerajinan, dan oleh-oleh dari berbagai daerah. Kenali produk serta asal UMKM-nya sebelum memilih.
        </p>
        <div class="flex flex-wrap gap-3">
          <RouterLink :to="{ name: 'katalog' }" class="btn bg-gray-900 text-white transition-colors hover:bg-black hover:shadow-md min-h-[48px] px-6">Belanja sekarang</RouterLink>
          <a href="#produk" class="btn-outline min-h-[48px] px-6">Lihat produk</a>
        </div>
      </div>
      <div
        v-if="heroProduct"
        class="group relative h-72 overflow-hidden rounded-[20px] bg-[#EDEDF0] md:h-96"
        aria-roledescription="carousel"
        aria-label="Produk pilihan UMKM"
      >
        <Transition
          mode="out-in"
          enter-active-class="transition-opacity duration-500 ease-in-out"
          enter-from-class="opacity-0"
          enter-to-class="opacity-100"
          leave-active-class="transition-opacity duration-500 ease-in-out"
          leave-from-class="opacity-100"
          leave-to-class="opacity-0"
        >
          <RouterLink
            :key="heroProduct.id"
            :to="{ name: 'produk', params: { slug: heroProduct.slug } }"
            class="absolute inset-0 flex items-end"
          >
            <img
              v-if="heroProduct.image_url"
              :src="heroProduct.image_url"
              :alt="heroProduct.product_name"
              class="absolute inset-0 h-full w-full object-cover transition duration-300 group-hover:scale-105"
            />
            <div v-else class="absolute inset-0 flex items-center justify-center text-sm text-[#4B5563]">Produk pilihan UMKM</div>
            <div class="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/80 to-transparent p-5 pb-12 pt-14 text-white">
              <p class="text-xs font-medium text-white/80">{{ heroProduct.umkm_name || 'Produk lokal pilihan' }}</p>
              <p class="mt-1 text-lg font-semibold">{{ heroProduct.product_name }}</p>
            </div>
          </RouterLink>
        </Transition>
        <div
          v-if="featuredProducts.length > 1"
          class="absolute inset-x-0 bottom-4 z-10 flex justify-center gap-2"
          role="group"
          aria-label="Pilih produk unggulan"
        >
          <button
            v-for="(product, index) in featuredProducts"
            :key="product.id"
            type="button"
            class="h-2.5 w-2.5 rounded-full transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white focus-visible:ring-offset-2 focus-visible:ring-offset-black/30"
            :class="index === currentIndex ? 'bg-white' : 'bg-white/50 hover:bg-white/75'"
            :aria-label="`Tampilkan ${product.product_name}`"
            :aria-pressed="index === currentIndex"
            @click="pilihSlide(index)"
          ></button>
        </div>
      </div>
      <div v-else class="flex h-72 items-center justify-center rounded-[20px] bg-[#EDEDF0] text-center text-sm text-[#4B5563] md:h-96">
        <span v-if="loading">Menyiapkan pilihan produk lokal…</span>
        <span v-else>Produk lokal pilihan segera hadir</span>
      </div>
    </section>

    <section class="mt-8 grid gap-3 sm:grid-cols-3">
      <article class="rounded-xl border border-line p-5">
        <p class="text-sm font-semibold">Temukan produk daerah</p>
        <p class="mt-2 text-sm leading-relaxed text-muted">Jelajahi kuliner, kerajinan, dan buah tangan dari berbagai kategori.</p>
      </article>
      <article class="rounded-xl border border-line p-5">
        <p class="text-sm font-semibold">Kenali asal produknya</p>
        <p class="mt-2 text-sm leading-relaxed text-muted">Lihat informasi UMKM dan daerah asal pada halaman setiap produk.</p>
      </article>
      <article class="rounded-xl border border-line p-5">
        <p class="text-sm font-semibold">Dukung UMKM lokal</p>
        <p class="mt-2 text-sm leading-relaxed text-muted">Setiap pilihan membantu karya dan usaha lokal menjangkau lebih banyak orang.</p>
      </article>
    </section>

    <section v-if="categories.length" class="mt-10">
      <div class="mb-4">
        <p class="text-xs font-semibold uppercase tracking-wider text-gold-dark">Mulai menjelajah</p>
        <h2 class="mt-1 text-xl font-semibold">Belanja per kategori</h2>
      </div>
      <div class="flex flex-wrap gap-3">
        <RouterLink
          v-for="c in categories"
          :key="c.id"
          :to="{ name: 'katalog', query: { kategori: c.slug } }"
          class="rounded-xl border border-gray-900 px-5 py-3 text-sm font-medium text-gray-900 hover:bg-gray-50"
        >{{ c.name }}</RouterLink>
      </div>
    </section>

    <section id="produk" class="mt-12 scroll-mt-6">
      <div class="mb-4 flex items-baseline justify-between">
        <div>
          <p class="text-xs font-semibold uppercase tracking-wider text-gold-dark">Dari para pelaku lokal</p>
          <h2 class="mt-1 text-xl font-semibold">Produk terbaru</h2>
        </div>
        <RouterLink :to="{ name: 'katalog' }" class="text-sm font-semibold">Lihat semua</RouterLink>
      </div>

      <p v-if="error" class="rounded-xl bg-bad-bg p-4 text-sm text-bad-fg" role="alert">
        Produk belum bisa dimuat: {{ error }}
        <button class="ml-2 font-semibold underline" type="button" @click="load">Coba lagi</button>
      </p>
      <div v-else-if="loading" class="grid grid-cols-2 gap-3 sm:gap-4 md:grid-cols-3 lg:grid-cols-5">
        <div v-for="n in 4" :key="n" class="aspect-square animate-pulse rounded-[14px] bg-surface"></div>
      </div>
      <p v-else-if="!products.length" class="rounded-xl bg-surface p-6 text-sm text-muted">
        Belum ada produk aktif. Produk akan muncul setelah UMKM menambahkan produk dan mengaktifkannya.
      </p>
      <div v-else class="grid grid-cols-2 gap-3 sm:gap-4 md:grid-cols-3 lg:grid-cols-5">
        <ProductCard v-for="p in products" :key="p.id" :product="p" />
      </div>
    </section>

    <section class="mt-14 flex flex-col items-start justify-between gap-5 rounded-2xl bg-ink p-7 text-white sm:flex-row sm:items-center sm:p-10">
      <div>
        <p class="text-sm font-semibold text-gold">PasarPintar</p>
        <h2 class="mt-2 max-w-xl text-2xl font-bold">Ada banyak cerita lokal untuk ditemukan.</h2>
        <p class="mt-2 max-w-xl text-sm leading-relaxed text-white/75">Jelajahi katalog dan temukan produk yang cocok untuk dinikmati atau dibagikan.</p>
      </div>
      <RouterLink :to="{ name: 'katalog' }" class="btn min-h-[48px] shrink-0 bg-white px-6 font-semibold text-gray-900 hover:bg-gray-50">
        Jelajahi katalog
      </RouterLink>
    </section>
  </div>
</template>
