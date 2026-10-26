<script setup>
import { computed, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue'
import { RouterLink } from 'vue-router'
import SellerDashboardSidebar from '@/components/SellerDashboardSidebar.vue'
import { CategoryScale, Chart as ChartJS, Filler, Legend, LinearScale, LineElement, PointElement, Tooltip } from 'chart.js'
import { Line } from 'vue-chartjs'
import { listCategories } from '@/services/catalogService'
import { deleteImage, uploadImage } from '@/services/adminProductService'
import { deleteMyUmkmProduct, getMyUmkm, getMyUmkmDashboardMetrics, listMyUmkmProducts, saveMyUmkmProduct } from '@/services/umkmPartnerService'
import { formatRupiah } from '@/lib/format'
import { slugify } from '@/lib/slug'

const umkm = ref(null)
const products = ref([])
const categories = ref([])
const metrics = ref(null)
const loading = ref(true)
const saving = ref(false)
const error = ref('')
const notice = ref('')
const search = ref('')
const formOpen = ref(false)
const editingId = ref(null)
const formError = ref('')
const savedImages = ref([])
const pendingImages = ref([])
const form = reactive({ name: '', slug: '', description: '', category_id: '', price: 0, stock: 0, is_active: true })
const slugTouched = ref(false)
ChartJS.register(CategoryScale, LinearScale, PointElement, LineElement, Tooltip, Legend, Filler)

const totalPendapatan = computed(() => Number(metrics.value?.total_pendapatan ?? 0))
const pesananBaru = computed(() => Number(metrics.value?.pesanan_baru ?? 0))
const salesChartData = computed(() => ({
  labels: (metrics.value?.pendapatan_harian ?? []).map((item) => new Intl.DateTimeFormat('id-ID', {
    weekday: 'short',
    timeZone: 'UTC',
  }).format(new Date(`${item.tanggal}T00:00:00Z`))),
  datasets: [{
    label: 'Pendapatan',
    data: (metrics.value?.pendapatan_harian ?? []).map((item) => Number(item.omzet)),
    borderColor: '#047857',
    backgroundColor: 'rgba(16, 185, 129, 0.12)',
    pointBackgroundColor: '#047857',
    pointBorderColor: '#ffffff',
    pointBorderWidth: 2,
    pointRadius: 4,
    pointHoverRadius: 6,
    borderWidth: 3,
    fill: true,
    tension: 0.35,
  }],
}))
const salesChartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  interaction: { intersect: false, mode: 'index' },
  plugins: {
    legend: { display: false },
    tooltip: {
      callbacks: {
        label: (context) => `${context.dataset.label}: ${formatRupiah(context.parsed.y)}`,
      },
    },
  },
  scales: {
    x: {
      grid: { display: false },
      ticks: { color: '#64748b' },
      border: { display: false },
    },
    y: {
      beginAtZero: true,
      ticks: { color: '#64748b', callback: (value) => formatRupiah(value) },
      grid: { color: '#e2e8f0', borderDash: [4, 4] },
      border: { display: false },
    },
  },
}
const filteredProducts = computed(() => {
  const query = search.value.trim().toLocaleLowerCase('id')
  if (!query) return products.value
  return products.value.filter((product) =>
    [product.name, product.description, product.categories?.name]
      .filter(Boolean)
      .some((value) => value.toLocaleLowerCase('id').includes(query)),
  )
})

watch(() => form.name, (name) => {
  if (!slugTouched.value) form.slug = slugify(name)
})

async function load() {
  loading.value = true
  error.value = ''
  try {
    umkm.value = await getMyUmkm()
    categories.value = await listCategories()
    if (umkm.value?.status === 'active' && umkm.value.is_active) {
      const [myProducts, dashboardMetrics] = await Promise.all([
        listMyUmkmProducts(umkm.value.id),
        getMyUmkmDashboardMetrics(umkm.value.id),
      ])
      products.value = myProducts
      metrics.value = dashboardMetrics
    } else {
      products.value = []
      metrics.value = null
    }
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}
onMounted(load)

function bersihkanFotoPending() {
  for (const photo of pendingImages.value) URL.revokeObjectURL(photo.url)
  pendingImages.value = []
}

onBeforeUnmount(bersihkanFotoPending)

function bukaForm(product = null) {
  bersihkanFotoPending()
  editingId.value = product?.id ?? null
  savedImages.value = [...(product?.product_images ?? [])].sort((a, b) => a.sort_order - b.sort_order)
  Object.assign(form, {
    name: product?.name ?? '',
    slug: product?.slug ?? '',
    description: product?.description ?? '',
    category_id: product?.category_id ?? '',
    price: product?.price ?? 0,
    stock: product?.stock ?? 0,
    is_active: product?.is_active ?? true,
  })
  slugTouched.value = !!product
  formError.value = ''
  formOpen.value = true
}

function tambahFoto(files) {
  formError.value = ''
  for (const file of files) {
    if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type)) {
      formError.value = 'Format foto harus JPG, PNG, atau WebP.'
      continue
    }
    if (file.size > 2 * 1024 * 1024) {
      formError.value = 'Ukuran foto maksimal 2 MB.'
      continue
    }
    pendingImages.value.push({ file, url: URL.createObjectURL(file) })
  }
}

function pilihFoto(event) {
  tambahFoto([...event.target.files])
  event.target.value = ''
}

function dropFoto(event) {
  tambahFoto([...event.dataTransfer.files])
}

function hapusFotoPending(index) {
  URL.revokeObjectURL(pendingImages.value[index].url)
  pendingImages.value.splice(index, 1)
}

function batalProduk() {
  bersihkanFotoPending()
  formOpen.value = false
}

async function hapusFotoTersimpan(image) {
  formError.value = ''
  try {
    await deleteImage(image)
    savedImages.value = savedImages.value.filter((item) => item.id !== image.id)
  } catch (error) {
    formError.value = error.message
  }
}

async function simpanProduk() {
  saving.value = true
  formError.value = ''
  notice.value = ''
  const wasEditing = Boolean(editingId.value)
  try {
    const fields = {
      name: form.name.trim(),
      slug: form.slug.trim(),
      description: form.description.trim() || null,
      category_id: form.category_id || null,
      price: Number(form.price),
      stock: Number(form.stock),
      is_active: form.is_active,
    }
    const productId = await saveMyUmkmProduct(editingId.value, umkm.value.id, fields)
    editingId.value = productId
    while (pendingImages.value.length) {
      const photo = pendingImages.value[0]
      const uploaded = await uploadImage(productId, photo.file)
      savedImages.value.push(uploaded)
      URL.revokeObjectURL(photo.url)
      pendingImages.value.shift()
    }
    formOpen.value = false
    notice.value = wasEditing ? 'Produk berhasil diperbarui.' : 'Produk berhasil ditambahkan.'
    bersihkanFotoPending()
    await load()
  } catch (e) {
    formError.value = e.message
  } finally {
    saving.value = false
  }
}

async function hapusProduk(product) {
  if (!confirm(`Hapus produk "${product.name}"?`)) return
  error.value = ''
  notice.value = ''
  try {
    await deleteMyUmkmProduct(product.id, umkm.value.id)
    notice.value = 'Produk berhasil dihapus.'
    await load()
  } catch (e) {
    error.value = e.message
  }
}
</script>

<template>
  <div class="min-h-full bg-slate-50 lg:flex">
    <SellerDashboardSidebar :umkm="umkm" />

    <main class="min-w-0 flex-1 px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
      <div class="mx-auto max-w-7xl">
        <section id="ringkasan" class="scroll-mt-6">
          <div class="flex flex-wrap items-end justify-between gap-4">
            <div>
              <p class="text-sm font-medium text-emerald-700">Dasbor penjual</p>
              <h1 class="mt-1 text-2xl font-bold tracking-tight text-slate-900 sm:text-3xl">Ringkasan Toko</h1>
              <p class="mt-1.5 text-sm text-slate-500">Pantau produk dan aktivitas toko {{ umkm?.name || 'Anda' }}.</p>
            </div>
            <span class="inline-flex items-center gap-2 rounded-full bg-emerald-50 px-3 py-1.5 text-xs font-semibold text-emerald-700">
              <span class="h-2 w-2 rounded-full bg-emerald-500"></span>
              Toko aktif
            </span>
          </div>

          <p v-if="notice" class="mt-5 rounded-xl border border-emerald-100 bg-emerald-50 p-3 text-sm text-emerald-800" role="status">{{ notice }}</p>
          <p v-if="error" class="mt-5 rounded-xl border border-red-100 bg-red-50 p-4 text-sm text-red-700" role="alert">
            {{ error }}
            <button class="ml-1 font-semibold underline" type="button" @click="load">Coba lagi</button>
          </p>

          <div v-if="loading" class="mt-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
            <div v-for="n in 3" :key="n" class="h-32 animate-pulse rounded-xl bg-white shadow-sm ring-1 ring-slate-200"></div>
          </div>
          <div v-else-if="!umkm" class="mt-6 rounded-xl border border-slate-200 bg-white p-6">
            <p class="font-semibold text-slate-900">Data UMKM tidak ditemukan.</p>
            <RouterLink :to="{ name: 'akun' }" class="mt-2 inline-block text-sm font-semibold text-emerald-700 underline">Periksa pendaftaran di halaman akun</RouterLink>
          </div>
          <div v-else-if="umkm.status !== 'active' || !umkm.is_active" class="mt-6 rounded-xl border border-amber-200 bg-amber-50 p-5 text-sm text-amber-900" role="status">
            Pendaftaran UMKM belum aktif. Fitur pengelolaan produk tersedia setelah Admin PasarPintar menyetujui pendaftaran.
          </div>
          <template v-else>
            <div class="mt-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
              <article class="rounded-xl bg-white p-5 shadow-sm ring-1 ring-slate-200">
                <div class="flex items-start justify-between">
                  <div>
                    <p class="text-sm font-medium text-slate-500">Total Produk</p>
                    <p class="mt-3 text-3xl font-bold tracking-tight text-slate-900">{{ products.length }}</p>
                    <p class="mt-1 text-xs text-slate-500">Produk di toko Anda</p>
                  </div>
                  <span class="rounded-lg bg-blue-50 p-2.5 text-blue-700">
                    <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
                      <path stroke-linecap="round" stroke-linejoin="round" d="m3 7 9-4 9 4-9 4-9-4Zm0 0v10l9 4 9-4V7M12 11v10" />
                    </svg>
                  </span>
                </div>
              </article>
              <article class="rounded-xl bg-white p-5 shadow-sm ring-1 ring-slate-200">
                <div class="flex items-start justify-between">
                  <div>
                    <p class="text-sm font-medium text-slate-500">Pesanan Baru</p>
                    <p class="mt-3 text-3xl font-bold tracking-tight text-slate-900">{{ pesananBaru }}</p>
                    <p class="mt-1 text-xs text-slate-500">Pesanan menunggu diproses</p>
                  </div>
                  <span class="rounded-lg bg-amber-50 p-2.5 text-amber-700">
                    <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M5 8h14l1 12H4L5 8Zm4 0a3 3 0 0 1 6 0M8 12h.01M16 12h.01" />
                    </svg>
                  </span>
                </div>
              </article>
              <article class="rounded-xl bg-white p-5 shadow-sm ring-1 ring-slate-200">
                <div class="flex items-start justify-between">
                  <div>
                    <p class="text-sm font-medium text-slate-500">Total Pendapatan</p>
                    <p class="mt-3 text-2xl font-bold tracking-tight text-slate-900">{{ formatRupiah(totalPendapatan) }}</p>
                    <p class="mt-1 text-xs text-slate-500">Akumulasi penjualan</p>
                  </div>
                  <span class="rounded-lg bg-emerald-50 p-2.5 text-emerald-700">
                    <svg viewBox="0 0 24 24" class="h-5 w-5" aria-hidden="true">
                      <text x="12" y="16" fill="currentColor" font-size="10" font-weight="700" text-anchor="middle">Rp</text>
                    </svg>
                  </span>
                </div>
              </article>
            </div>
            <section class="mt-6 w-full rounded-xl bg-white p-5 shadow-sm ring-1 ring-slate-200 sm:p-6" aria-labelledby="sales-chart-title">
              <div class="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <h2 id="sales-chart-title" class="text-lg font-semibold text-slate-900">Pendapatan 7 Hari Terakhir</h2>
                  <p class="mt-1 text-sm text-slate-500">Visualisasi pendapatan harian toko.</p>
                </div>
              </div>
              <p v-if="!metrics?.pendapatan_harian?.some((item) => Number(item.omzet) > 0)" class="mt-5 rounded-lg bg-slate-50 p-4 text-sm text-slate-500">Belum ada pendapatan pada tujuh hari terakhir.</p>
              <div v-else class="mt-5 h-[300px]">
                <Line :data="salesChartData" :options="salesChartOptions" />
              </div>
            </section>
          </template>
        </section>

        <section v-if="umkm?.status === 'active' && umkm.is_active" id="produk-saya" class="mt-8 scroll-mt-6 rounded-xl bg-white p-4 shadow-sm ring-1 ring-slate-200 sm:p-6">
          <div class="flex flex-col gap-4 border-b border-slate-100 pb-5 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <h2 class="text-lg font-semibold text-slate-900">Produk Saya</h2>
              <p class="mt-1 text-sm text-slate-500">Kelola katalog, harga, dan stok produk toko.</p>
            </div>
            <div class="flex flex-col gap-3 sm:flex-row">
              <label class="relative block sm:w-64">
                <span class="sr-only">Cari produk</span>
                <svg viewBox="0 0 24 24" class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                  <circle cx="11" cy="11" r="7" /><path stroke-linecap="round" d="m16 16 4 4" />
                </svg>
                <input v-model="search" class="min-h-11 w-full rounded-lg border border-slate-200 bg-white pl-9 pr-3 text-sm outline-none transition placeholder:text-slate-400 focus:border-emerald-600 focus:ring-2 focus:ring-emerald-100" type="search" placeholder="Cari nama produk..." />
              </label>
              <button class="inline-flex min-h-11 items-center justify-center gap-2 rounded-lg bg-emerald-700 px-4 text-sm font-semibold text-white transition hover:bg-emerald-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-600 focus-visible:ring-offset-2" type="button" @click="bukaForm()">
                <svg viewBox="0 0 24 24" class="h-4 w-4" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                  <path stroke-linecap="round" d="M12 5v14M5 12h14" />
                </svg>
                Tambah produk
              </button>
            </div>
          </div>

          <div v-if="products.length" class="mt-4 w-full overflow-x-auto">
            <table class="w-full min-w-[760px] text-left text-sm">
              <thead>
                <tr class="border-b border-slate-200 text-xs uppercase tracking-wide text-slate-500">
                  <th class="px-3 py-3 font-semibold">Produk</th>
                  <th class="px-3 py-3 font-semibold">Kategori</th>
                  <th class="px-3 py-3 font-semibold">Harga</th>
                  <th class="px-3 py-3 font-semibold">Stok</th>
                  <th class="px-3 py-3 font-semibold">Status</th>
                  <th class="px-3 py-3 text-right font-semibold">Aksi</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="product in filteredProducts" :key="product.id" class="border-b border-slate-100 transition last:border-0 hover:bg-slate-50/80">
                  <td class="px-3 py-4">
                    <div class="flex items-center gap-3">
                      <img
                        v-if="product.product_images?.[0]?.url"
                        :src="product.product_images[0].url"
                        :alt="product.name"
                        class="h-11 w-11 rounded-lg object-cover"
                      />
                      <span v-else class="flex h-11 w-11 items-center justify-center rounded-lg bg-slate-100 text-slate-400">
                        <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true">
                          <rect x="3" y="3" width="18" height="18" rx="2" /><circle cx="8.5" cy="8.5" r="1.5" /><path stroke-linecap="round" stroke-linejoin="round" d="m21 15-5-5L5 21" />
                        </svg>
                      </span>
                      <div class="min-w-0">
                        <p class="truncate font-semibold text-slate-900">{{ product.name }}</p>
                        <p class="mt-0.5 max-w-xs truncate text-xs text-slate-500">{{ product.description || 'Tanpa deskripsi' }}</p>
                      </div>
                    </div>
                  </td>
                  <td class="px-3 py-4 text-slate-600">{{ product.categories?.name || 'Tanpa kategori' }}</td>
                  <td class="px-3 py-4 font-medium text-slate-800">{{ formatRupiah(product.price) }}</td>
                  <td class="px-3 py-4 text-slate-600">{{ product.stock }}</td>
                  <td class="px-3 py-4">
                    <span class="inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-medium" :class="product.is_active ? 'bg-emerald-50 text-emerald-700' : 'bg-slate-100 text-slate-600'">
                      <span class="h-1.5 w-1.5 rounded-full" :class="product.is_active ? 'bg-emerald-500' : 'bg-slate-400'"></span>
                      {{ product.is_active ? 'Aktif' : 'Nonaktif' }}
                    </span>
                  </td>
                  <td class="whitespace-nowrap px-3 py-4 text-right">
                    <button class="rounded-md px-2 py-1.5 text-xs font-semibold text-emerald-700 transition hover:bg-emerald-50" type="button" @click="bukaForm(product)">Ubah</button>
                    <button class="rounded-md px-2 py-1.5 text-xs font-semibold text-red-600 transition hover:bg-red-50" type="button" @click="hapusProduk(product)">Hapus</button>
                  </td>
                </tr>
                <tr v-if="!filteredProducts.length">
                  <td colspan="6" class="px-3 py-10 text-center text-sm text-slate-500">Tidak ada produk yang cocok dengan pencarian.</td>
                </tr>
              </tbody>
            </table>
          </div>
          <div v-else class="py-12 text-center">
            <div class="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-slate-100 text-slate-500">
              <svg viewBox="0 0 24 24" class="h-6 w-6" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" d="m3 7 9-4 9 4-9 4-9-4Zm0 0v10l9 4 9-4V7M12 11v10" />
              </svg>
            </div>
            <h3 class="mt-3 text-sm font-semibold text-slate-900">Belum ada produk</h3>
            <p class="mt-1 text-sm text-slate-500">Tambahkan produk pertama untuk mulai mengisi katalog toko.</p>
            <button class="mt-4 text-sm font-semibold text-emerald-700 hover:text-emerald-800" type="button" @click="bukaForm()">Tambah produk pertama</button>
          </div>
        </section>

        <section v-if="formOpen" class="mt-6 rounded-xl bg-white p-5 shadow-sm ring-1 ring-slate-200 sm:p-6">
          <div class="flex items-start justify-between gap-4">
            <div>
              <h2 class="text-lg font-semibold text-slate-900">{{ editingId ? 'Ubah produk' : 'Tambah produk' }}</h2>
              <p class="mt-1 text-sm text-slate-500">Lengkapi informasi produk untuk toko Anda.</p>
            </div>
            <button class="rounded-lg p-2 text-slate-500 hover:bg-slate-100 hover:text-slate-900" type="button" aria-label="Tutup form" @click="batalProduk">
              <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                <path stroke-linecap="round" d="m6 6 12 12M18 6 6 18" />
              </svg>
            </button>
          </div>
          <form class="mt-5 grid gap-4 md:grid-cols-2" @submit.prevent="simpanProduk">
            <div>
              <label for="seller-product-name" class="mb-1.5 block text-sm font-medium text-slate-700">Nama produk</label>
              <input id="seller-product-name" v-model="form.name" class="input" maxlength="120" required />
            </div>
            <div>
              <label for="seller-product-slug" class="mb-1.5 block text-sm font-medium text-slate-700">Slug</label>
              <input id="seller-product-slug" v-model="form.slug" class="input" pattern="[a-z0-9]+(-[a-z0-9]+)*" required @input="slugTouched = true" />
            </div>
            <div>
              <label for="seller-product-category" class="mb-1.5 block text-sm font-medium text-slate-700">Kategori</label>
              <select id="seller-product-category" v-model="form.category_id" class="input">
                <option value="">Tanpa kategori</option>
                <option v-for="category in categories" :key="category.id" :value="category.id">{{ category.name }}</option>
              </select>
            </div>
            <div class="grid grid-cols-2 gap-3">
              <div>
                <label for="seller-product-price" class="mb-1.5 block text-sm font-medium text-slate-700">Harga (Rp)</label>
                <input id="seller-product-price" v-model.number="form.price" class="input" type="number" min="0" step="1" required />
              </div>
              <div>
                <label for="seller-product-stock" class="mb-1.5 block text-sm font-medium text-slate-700">Stok</label>
                <input id="seller-product-stock" v-model.number="form.stock" class="input" type="number" min="0" step="1" required />
              </div>
            </div>
            <div class="md:col-span-2">
              <label for="seller-product-description" class="mb-1.5 block text-sm font-medium text-slate-700">Deskripsi</label>
              <textarea id="seller-product-description" v-model="form.description" class="input py-2" rows="4"></textarea>
            </div>
            <div class="md:col-span-2">
              <h3 class="text-sm font-medium text-slate-700">Foto produk</h3>
              <p class="mt-1 text-xs text-slate-500">JPG, PNG, atau WebP · Maksimal 2 MB per foto</p>
              <label for="seller-product-photo" class="mt-3 flex min-h-40 cursor-pointer flex-col items-center justify-center rounded-xl border-2 border-dashed border-slate-300 bg-slate-50 p-5 text-center transition hover:border-emerald-500 hover:bg-emerald-50/50" @dragover.prevent @drop.prevent="dropFoto">
                <svg viewBox="0 0 24 24" class="h-9 w-9 text-slate-400" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M12 16V4m0 0L7.5 8.5M12 4l4.5 4.5M5 14v5h14v-5" />
                </svg>
                <span class="mt-2 text-sm font-semibold text-slate-700">Tarik foto ke sini atau klik untuk memilih</span>
                <span class="mt-1 text-xs text-slate-500">Foto baru diunggah saat produk disimpan</span>
                <input id="seller-product-photo" class="sr-only" type="file" accept="image/*" multiple @change="pilihFoto" />
              </label>
              <div v-if="pendingImages.length || savedImages.length" class="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-4">
                <div v-for="(photo, index) in pendingImages" :key="photo.url" class="relative">
                  <img :src="photo.url" :alt="photo.file.name" class="aspect-square w-full rounded-xl object-cover" />
                  <button type="button" class="absolute right-2 top-2 rounded-lg bg-white/95 px-2.5 py-1.5 text-xs font-semibold text-slate-800 shadow" @click="hapusFotoPending(index)">Hapus / Ganti</button>
                </div>
                <div v-for="image in savedImages" :key="image.id" class="relative">
                  <img :src="image.url" alt="Foto produk tersimpan" class="aspect-square w-full rounded-xl object-cover" />
                  <button type="button" class="absolute right-2 top-2 rounded-lg bg-white/95 px-2.5 py-1.5 text-xs font-semibold text-red-600 shadow" @click="hapusFotoTersimpan(image)">Hapus foto</button>
                </div>
              </div>
            </div>
            <label class="flex items-center gap-2 text-sm text-slate-700 md:col-span-2"><input v-model="form.is_active" type="checkbox" /> Tampilkan di katalog</label>
            <p v-if="formError" class="rounded-xl bg-red-50 p-3 text-sm text-red-700 md:col-span-2" role="alert">{{ formError }}</p>
            <div class="flex gap-2 md:col-span-2">
              <button class="inline-flex min-h-11 items-center justify-center rounded-lg bg-emerald-700 px-4 text-sm font-semibold text-white hover:bg-emerald-800 disabled:opacity-50" type="submit" :disabled="saving">{{ saving ? 'Menyimpan…' : 'Simpan produk' }}</button>
              <button class="btn-outline" type="button" :disabled="saving" @click="batalProduk">Batal</button>
            </div>
          </form>
        </section>
      </div>
    </main>
  </div>
</template>
