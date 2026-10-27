<script setup>
import { computed, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue'
import { RouterLink } from 'vue-router'
import SellerDashboardSidebar from '@/components/SellerDashboardSidebar.vue'
import { listCategories } from '@/services/catalogService'
import { deleteImage, uploadImage } from '@/services/adminProductService'
import { deleteMyUmkmProduct, getMyUmkm, listMyUmkmProducts, saveMyUmkmProduct } from '@/services/umkmPartnerService'
import { formatRupiah } from '@/lib/format'
import { slugify } from '@/lib/slug'

const umkm = ref(null)
const products = ref([])
const categories = ref([])
const loading = ref(true)
const saving = ref(false)
const error = ref('')
const notice = ref('')
const search = ref('')
const stockFilter = ref('all')
const formOpen = ref(false)
const editingId = ref(null)
const formError = ref('')
const savedImages = ref([])
const pendingImages = ref([])
const form = reactive({ name: '', slug: '', description: '', category_id: '', price: 0, stock: 0, is_active: true })
const slugTouched = ref(false)
const filteredProducts = computed(() => {
  const query = search.value.trim().toLocaleLowerCase('id')
  return products.value.filter((product) =>
    (stockFilter.value === 'all'
      || (stockFilter.value === 'active' && product.is_active && Number(product.stock) > 0)
      || (stockFilter.value === 'out' && Number(product.stock) <= 0))
    && (!query || [product.name, product.description, product.categories?.name]
      .filter(Boolean)
      .some((value) => value.toLocaleLowerCase('id').includes(query))),
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
      products.value = await listMyUmkmProducts(umkm.value.id)
    } else {
      products.value = []
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
    const name = form.name.trim()
    const slug = form.slug.trim()
    if (!name) throw new Error('Nama produk wajib diisi.')
    if (!slug) throw new Error('Slug produk wajib diisi.')

    const fields = {
      name,
      slug,
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

function duplikatProduk(product) {
  const slugSuffix = Date.now().toString(36)
  bukaForm({
    ...product,
    id: null,
    name: `${product.name} (salinan)`,
    slug: `${product.slug}-salinan-${slugSuffix}`,
    product_images: [],
  })
  savedImages.value = []
  notice.value = 'Salinan produk disiapkan tanpa foto. Simpan untuk membuat produk baru.'
}
</script>

<template>
  <div class="min-h-full bg-slate-50 lg:flex">
    <SellerDashboardSidebar :umkm="umkm" />

    <main class="min-w-0 flex-1 px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
      <div class="mx-auto max-w-7xl">
        <section id="produk-saya" class="scroll-mt-6">
          <div class="flex flex-wrap items-end justify-between gap-4">
            <div>
              <p class="text-sm font-medium text-emerald-700">Dasbor penjual</p>
              <h1 class="mt-1 text-2xl font-bold tracking-tight text-slate-900 sm:text-3xl">Produk Saya</h1>
              <p class="mt-1.5 text-sm text-slate-500">Kelola katalog, harga, dan stok produk {{ umkm?.name || 'toko Anda' }}.</p>
            </div>
            <RouterLink :to="{ name: 'umkm-dashboard' }" class="text-sm font-semibold text-emerald-700 hover:text-emerald-800">Lihat ringkasan →</RouterLink>
          </div>
          <p v-if="notice" class="mt-5 rounded-xl border border-emerald-100 bg-emerald-50 p-3 text-sm text-emerald-800" role="status">{{ notice }}</p>
          <p v-if="error" class="mt-5 rounded-xl border border-red-100 bg-red-50 p-4 text-sm text-red-700" role="alert">
            {{ error }}
            <button class="ml-1 font-semibold underline" type="button" @click="load">Coba lagi</button>
          </p>
          <div v-if="loading" class="mt-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
            <div v-for="n in 3" :key="n" class="h-64 animate-pulse rounded-2xl bg-white shadow-sm ring-1 ring-slate-200"></div>
          </div>
          <div v-else-if="!umkm" class="mt-6 rounded-xl border border-slate-200 bg-white p-6">
            <p class="font-semibold text-slate-900">Data UMKM tidak ditemukan.</p>
            <RouterLink :to="{ name: 'akun' }" class="mt-2 inline-block text-sm font-semibold text-emerald-700 underline">Periksa pendaftaran di halaman akun</RouterLink>
          </div>
          <div v-else-if="umkm.status !== 'active' || !umkm.is_active" class="mt-6 rounded-xl border border-amber-200 bg-amber-50 p-5 text-sm text-amber-900" role="status">
            Pengelolaan produk tersedia setelah Admin PasarPintar menyetujui dan mengaktifkan toko.
          </div>
          <section v-else class="mt-6 rounded-2xl bg-white p-4 shadow-sm ring-1 ring-slate-200 sm:p-6">
          <div class="flex flex-col gap-4 border-b border-slate-100 pb-5 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <h2 class="text-lg font-semibold text-slate-900">Katalog produk</h2>
              <p class="mt-1 text-sm text-slate-500">{{ filteredProducts.length }} dari {{ products.length }} produk</p>
            </div>
            <div class="grid gap-3 sm:grid-cols-[minmax(14rem,1fr)_10rem_auto]">
              <label class="relative block sm:w-64">
                <span class="sr-only">Cari produk</span>
                <svg viewBox="0 0 24 24" class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                  <circle cx="11" cy="11" r="7" /><path stroke-linecap="round" d="m16 16 4 4" />
                </svg>
                <input v-model="search" class="min-h-11 w-full rounded-lg border border-slate-200 bg-white pl-9 pr-3 text-sm outline-none transition placeholder:text-slate-400 focus:border-emerald-600 focus:ring-2 focus:ring-emerald-100" type="search" placeholder="Cari nama produk..." />
              </label>
              <label class="block">
                <span class="sr-only">Filter produk</span>
                <select v-model="stockFilter" class="min-h-11 w-full rounded-lg border border-slate-200 bg-white px-3 text-sm text-slate-700 outline-none focus:border-emerald-600 focus:ring-2 focus:ring-emerald-100">
                  <option value="all">Semua produk</option>
                  <option value="active">Aktif</option>
                  <option value="out">Habis</option>
                </select>
              </label>
              <button class="inline-flex min-h-11 items-center justify-center gap-2 rounded-lg bg-emerald-700 px-4 text-sm font-semibold text-white transition hover:bg-emerald-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-600 focus-visible:ring-offset-2" type="button" @click="bukaForm()">
                <svg viewBox="0 0 24 24" class="h-4 w-4" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                  <path stroke-linecap="round" d="M12 5v14M5 12h14" />
                </svg>
                Tambah produk
              </button>
            </div>
          </div>

          <div v-if="filteredProducts.length" class="mt-5 grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
            <article v-for="product in filteredProducts" :key="product.id" class="group overflow-hidden rounded-2xl border border-slate-200 bg-white transition-all duration-300 hover:-translate-y-1 hover:border-emerald-200 hover:shadow-lg">
              <div class="relative aspect-[4/3] overflow-hidden bg-slate-100">
                <img v-if="product.product_images?.[0]?.url" :src="product.product_images[0].url" :alt="product.name" class="h-full w-full object-cover transition duration-500 group-hover:scale-105" />
                <div v-else class="flex h-full items-center justify-center text-slate-400">
                  <svg viewBox="0 0 24 24" class="h-12 w-12" fill="none" stroke="currentColor" stroke-width="1.4" aria-hidden="true"><rect x="3" y="3" width="18" height="18" rx="2" /><circle cx="8.5" cy="8.5" r="1.5" /><path stroke-linecap="round" stroke-linejoin="round" d="m21 15-5-5L5 21" /></svg>
                </div>
                <span class="absolute left-3 top-3 rounded-full px-3 py-1 text-xs font-semibold" :class="Number(product.stock) > 0 ? 'bg-emerald-100 text-emerald-800' : 'bg-red-100 text-red-700'">{{ Number(product.stock) > 0 ? `Tersedia · ${product.stock}` : 'Habis' }}</span>
                <span v-if="!product.is_active" class="absolute right-3 top-3 rounded-full bg-slate-800/80 px-3 py-1 text-xs font-semibold text-white">Nonaktif</span>
              </div>
              <div class="p-4">
                <p class="text-xs font-medium uppercase tracking-wide text-slate-500">{{ product.categories?.name || 'Tanpa kategori' }}</p>
                <h3 class="mt-1 truncate text-lg font-bold text-slate-900">{{ product.name }}</h3>
                <p class="mt-1 min-h-10 line-clamp-2 text-sm text-slate-500">{{ product.description || 'Tanpa deskripsi' }}</p>
                <p class="mt-3 text-lg font-bold text-emerald-700">{{ formatRupiah(product.price) }}</p>
                <div class="mt-4 flex flex-wrap gap-2 border-t border-slate-100 pt-3">
                  <button class="rounded-lg bg-emerald-50 px-3 py-2 text-xs font-semibold text-emerald-800 transition hover:bg-emerald-100" type="button" @click="bukaForm(product)">Ubah</button>
                  <button class="rounded-lg bg-blue-50 px-3 py-2 text-xs font-semibold text-blue-800 transition hover:bg-blue-100" type="button" @click="duplikatProduk(product)">Duplikat</button>
                  <button class="rounded-lg bg-red-50 px-3 py-2 text-xs font-semibold text-red-700 transition hover:bg-red-100" type="button" @click="hapusProduk(product)">Hapus</button>
                </div>
              </div>
            </article>
          </div>
          <div v-else-if="products.length" class="py-12 text-center text-sm text-slate-500">Tidak ada produk yang cocok dengan pencarian atau filter.</div>
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
