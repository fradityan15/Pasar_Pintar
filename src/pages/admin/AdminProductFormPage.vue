<script setup>
import { computed, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue'
import { RouterLink, useRoute, useRouter } from 'vue-router'
import AdminPageHeader from '@/components/AdminPageHeader.vue'
import { deleteImage, getAdminProduct, makeMainImage, saveProduct, uploadImage } from '@/services/adminProductService'
import { listCategoriesAdmin, listUmkmAdmin } from '@/services/adminCatalogService'
import { slugify } from '@/lib/slug'

const route = useRoute()
const router = useRouter()
const productId = computed(() => route.params.id)
const isNew = computed(() => !productId.value)

const form = reactive({ name: '', slug: '', umkm_id: '', category_id: '', price: 0, stock: 0, weight_gram: 0, description: '', is_active: true })
const slugTouched = ref(false)
const umkms = ref([])
const categories = ref([])
const images = ref([])
const pending = ref([])
const loading = ref(true)
const saving = ref(false)
const error = ref('')
const info = ref('')

const categoryOptions = computed(() => {
  const byId = new Map(categories.value.map((c) => [c.id, c]))
  return categories.value
    .map((c) => ({ id: c.id, label: c.parent_id ? `${byId.get(c.parent_id)?.name} › ${c.name}` : c.name }))
    .sort((a, b) => a.label.localeCompare(b.label))
})
const sortedImages = computed(() => [...images.value].sort((a, b) => a.sort_order - b.sort_order))

watch(() => form.name, (v) => { if (!slugTouched.value) form.slug = slugify(v) })

async function loadImages(id = productId.value) {
  images.value = (await getAdminProduct(id))?.product_images ?? []
}

function tambahFoto(files) {
  error.value = ''
  for (const file of files) {
    if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type)) {
      error.value = 'Format foto harus JPG, PNG, atau WebP.'
      continue
    }
    if (file.size > 2 * 1024 * 1024) {
      error.value = 'Ukuran foto maksimal 2 MB.'
      continue
    }
    pending.value.push({ file, url: URL.createObjectURL(file) })
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
  URL.revokeObjectURL(pending.value[index].url)
  pending.value.splice(index, 1)
}

function bersihkanFotoPending() {
  for (const photo of pending.value) URL.revokeObjectURL(photo.url)
  pending.value = []
}

async function unggahFoto(productId) {
  while (pending.value.length) {
    const photo = pending.value[0]
    await uploadImage(productId, photo.file)
    URL.revokeObjectURL(photo.url)
    pending.value.shift()
  }
}

onBeforeUnmount(bersihkanFotoPending)

onMounted(async () => {
  try {
    ;[umkms.value, categories.value] = await Promise.all([listUmkmAdmin(), listCategoriesAdmin()])
    if (!isNew.value) {
      const p = await getAdminProduct(productId.value)
      if (!p) { error.value = 'Produk tidak ditemukan.'; return }
      Object.assign(form, {
        name: p.name, slug: p.slug, umkm_id: p.umkm_id, category_id: p.category_id ?? '', price: p.price,
        stock: p.stock, weight_gram: p.weight_gram, description: p.description ?? '', is_active: p.is_active,
      })
      slugTouched.value = true
      images.value = p.product_images
    }
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
})

async function hapusFoto(img) {
  if (!confirm('Hapus foto ini?')) return
  try { await deleteImage(img); await loadImages() } catch (e) { error.value = e.message }
}
async function jadikanUtama(img) {
  try { await makeMainImage(productId.value, img.id); await loadImages() } catch (e) { error.value = e.message }
}

async function simpan() {
  saving.value = true
  error.value = ''
  info.value = ''
  const fields = {
    name: form.name.trim(), slug: form.slug.trim(), umkm_id: form.umkm_id, category_id: form.category_id || null,
    description: form.description.trim() || null, price: Number(form.price), weight_gram: Number(form.weight_gram), is_active: form.is_active,
  }
  try {
    if (isNew.value) {
      const id = await saveProduct(null, { ...fields, stock: Number(form.stock) })
      await router.replace({ name: 'admin-produk-edit', params: { id } })
      await unggahFoto(id)
      await loadImages(id)
      info.value = 'Produk ditambahkan.'
    } else {
      await saveProduct(productId.value, fields)
      await unggahFoto(productId.value)
      await loadImages()
      info.value = 'Produk dan foto disimpan.'
    }
  } catch (e) {
    error.value = e.message
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <RouterLink :to="{ name: 'admin-produk' }" class="text-sm font-medium text-muted">← Semua produk</RouterLink>
  <AdminPageHeader class="mt-3" :title="isNew ? 'Tambah produk' : 'Ubah produk'" />

  <div v-if="loading" class="h-64 animate-pulse rounded-xl bg-white"></div>
  <form v-else class="grid gap-4 lg:grid-cols-[1fr_340px]" @submit.prevent="simpan">
    <section class="card flex flex-col gap-4 p-5">
      <div><label for="f-nama" class="mb-1.5 block text-sm font-medium">Nama produk</label><input id="f-nama" v-model="form.name" class="input" required /></div>
      <div>
        <label for="f-slug" class="mb-1.5 block text-sm font-medium">Slug (alamat halaman)</label>
        <input id="f-slug" v-model="form.slug" class="input" pattern="[a-z0-9]+(-[a-z0-9]+)*" required @input="slugTouched = true" />
        <p class="mt-1 text-xs text-muted">Huruf kecil, angka, dan tanda hubung. Terisi otomatis dari nama.</p>
      </div>
      <div class="grid gap-4 sm:grid-cols-2">
        <div>
          <label for="f-umkm" class="mb-1.5 block text-sm font-medium">UMKM</label>
          <select id="f-umkm" v-model="form.umkm_id" class="input" required>
            <option value="" disabled>Pilih UMKM</option>
            <option v-for="u in umkms" :key="u.id" :value="u.id">{{ u.name }}</option>
          </select>
        </div>
        <div>
          <label for="f-kat" class="mb-1.5 block text-sm font-medium">Kategori</label>
          <select id="f-kat" v-model="form.category_id" class="input">
            <option value="">Tanpa kategori</option>
            <option v-for="c in categoryOptions" :key="c.id" :value="c.id">{{ c.label }}</option>
          </select>
        </div>
        <div><label for="f-harga" class="mb-1.5 block text-sm font-medium">Harga (Rp)</label><input id="f-harga" v-model="form.price" class="input" type="number" min="0" step="1" required /></div>
        <div><label for="f-berat" class="mb-1.5 block text-sm font-medium">Berat (gram)</label><input id="f-berat" v-model="form.weight_gram" class="input" type="number" min="0" step="1" /></div>
        <div v-if="isNew"><label for="f-stok" class="mb-1.5 block text-sm font-medium">Stok awal</label><input id="f-stok" v-model="form.stock" class="input" type="number" min="0" step="1" required /></div>
        <div v-else>
          <p class="mb-1.5 text-sm font-medium">Stok</p>
          <p class="flex min-h-[44px] items-center rounded-xl bg-surface px-3.5 text-sm">{{ form.stock }} <span class="ml-2 text-xs text-muted">ubah lewat "Atur stok" di daftar produk</span></p>
        </div>
      </div>
      <div><label for="f-desk" class="mb-1.5 block text-sm font-medium">Deskripsi</label><textarea id="f-desk" v-model="form.description" class="input py-2" rows="5"></textarea></div>
      <label class="flex items-center gap-2 text-sm"><input v-model="form.is_active" type="checkbox" /> Tampilkan di toko (aktif)</label>

      <p v-if="error" class="rounded-xl bg-bad-bg p-3 text-sm text-bad-fg" role="alert">{{ error }}</p>
      <p v-if="info" class="rounded-xl bg-ok-bg p-3 text-sm text-ok-fg" role="status">{{ info }}</p>
      <div class="flex gap-2">
        <button class="btn-primary" type="submit" :disabled="saving">{{ saving ? 'Menyimpan…' : 'Simpan produk' }}</button>
        <RouterLink :to="{ name: 'admin-produk' }" class="btn-outline">Batal</RouterLink>
      </div>
    </section>

    <section class="card h-fit p-5">
      <h2 class="text-base font-semibold">Foto produk</h2>
      <p class="mt-1 text-xs text-muted">JPG, PNG, atau WebP, maksimal 2 MB. Foto pertama jadi foto utama.</p>

      <label
        for="f-foto"
        class="mt-4 flex min-h-40 cursor-pointer flex-col items-center justify-center rounded-xl border-2 border-dashed border-line bg-surface p-5 text-center transition hover:border-gray-900 hover:bg-gray-50"
        @dragover.prevent
        @drop.prevent="dropFoto"
      >
        <svg viewBox="0 0 24 24" class="h-9 w-9 text-muted" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true">
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 16V4m0 0L7.5 8.5M12 4l4.5 4.5M5 14v5h14v-5" />
        </svg>
        <span class="mt-2 text-sm font-semibold">Tarik foto ke sini atau klik untuk memilih</span>
        <span class="mt-1 text-xs text-muted">JPG, PNG, atau WebP · Maksimal 2 MB per foto</span>
        <input id="f-foto" class="sr-only" type="file" accept="image/*" multiple @change="pilihFoto" />
      </label>

      <ul v-if="pending.length" class="mt-3 grid grid-cols-2 gap-3">
        <li v-for="(photo, index) in pending" :key="photo.url" class="relative">
          <img :src="photo.url" :alt="photo.file.name" class="aspect-square w-full rounded-xl object-cover" />
          <button
            type="button"
            class="absolute right-2 top-2 rounded-lg bg-white/95 px-2.5 py-1.5 text-xs font-semibold text-gray-900 shadow"
            @click="hapusFotoPending(index)"
          >Hapus / Ganti</button>
        </li>
      </ul>

      <ul v-if="sortedImages.length" class="mt-3 grid grid-cols-2 gap-3">
        <li v-for="(img, i) in sortedImages" :key="img.id" class="text-xs">
          <img :src="img.url" alt="" class="aspect-square w-full rounded-xl object-cover" />
          <div class="mt-1.5 flex items-center justify-between gap-1">
            <span v-if="i === 0" class="badge bg-ok-bg text-ok-fg">Utama</span>
            <button v-else type="button" class="font-semibold underline" @click="jadikanUtama(img)">Jadikan utama</button>
            <button type="button" class="font-semibold text-gray-900 underline" @click="hapusFoto(img)">Hapus</button>
          </div>
        </li>
      </ul>
      <p class="mt-2 text-xs text-muted">Foto baru diunggah saat Anda menyimpan produk.</p>
    </section>
  </form>
</template>
