<script setup>
import { ref, watch } from 'vue'
import AdminPageHeader from '@/components/AdminPageHeader.vue'
import ModalDialog from '@/components/ModalDialog.vue'
import PaginationBar from '@/components/PaginationBar.vue'
import { useQueryState } from '@/composables/useQueryState'
import { getAdminProduct, listAdminProducts, setProductActive } from '@/services/adminProductService'
import { formatRupiah, formatTanggalJam } from '@/lib/format'

const { route, str, num, set } = useQueryState()
const items = ref([])
const total = ref(0)
const loading = ref(true)
const error = ref('')
const notice = ref('')
const search = ref(str('q'))
const tabs = [['', 'Semua'], ['aktif', 'Aktif'], ['menipis', 'Stok menipis'], ['nonaktif', 'Nonaktif']]
let req = 0

const detailOpen = ref(false)
const detail = ref(null)
const detailLoading = ref(false)
const detailError = ref('')
const moderatingId = ref(null)

const thumb = (p) => [...(p.product_images ?? [])].sort((a, b) => a.sort_order - b.sort_order)[0]?.url
const detailThumb = (p) => [...(p?.product_images ?? [])].sort((a, b) => a.sort_order - b.sort_order)

async function load() {
  const id = ++req
  loading.value = true
  error.value = ''
  try {
    const r = await listAdminProducts({ q: str('q'), status: str('status'), page: num('page') })
    if (id !== req) return
    items.value = r.items
    total.value = r.total
  } catch (e) {
    if (id === req) error.value = e.message
  } finally {
    if (id === req) loading.value = false
  }
}
watch(() => route.query, () => { if (route.name === 'admin-produk') load() }, { immediate: true })

async function toggle(p) {
  if (!p.is_active || moderatingId.value) return
  if (!confirm(`Nonaktifkan produk "${p.name}"? Produk tidak akan tampil di katalog pelanggan.`)) return
  moderatingId.value = p.id
  notice.value = ''
  try {
    await setProductActive(p.id, false)
    notice.value = `${p.name} dinonaktifkan.`
    await load()
  } catch (e) {
    error.value = e.message
  } finally {
    moderatingId.value = null
  }
}

async function lihatDetail(product) {
  detailOpen.value = true
  detailLoading.value = true
  detailError.value = ''
  detail.value = null
  try {
    detail.value = await getAdminProduct(product.id)
    if (!detail.value) detailError.value = 'Produk tidak ditemukan.'
  } catch (e) {
    detailError.value = e.message
  } finally {
    detailLoading.value = false
  }
}
</script>

<template>
  <AdminPageHeader title="Produk" desc="Pantau dan moderasi produk yang diunggah oleh Mitra UMKM." />

  <div class="card p-5">
    <div class="flex flex-wrap gap-x-5 border-b border-line" role="tablist" aria-label="Filter produk">
      <button
        v-for="[val, label] in tabs" :key="val" type="button" role="tab" :aria-selected="str('status') === val"
        class="-mb-px border-b-2 px-1 py-3 text-sm"
        :class="str('status') === val ? 'border-gray-900 font-semibold text-gray-900' : 'border-transparent text-muted'"
        @click="set({ status: val, page: 1 })"
      >{{ label }}</button>
    </div>

    <form class="flex gap-2 py-4" role="search" @submit.prevent="set({ q: search.trim(), page: 1 })">
      <label for="cari-produk" class="sr-only">Cari produk</label>
      <input id="cari-produk" v-model="search" class="input max-w-sm" type="search" placeholder="Cari nama produk" />
      <button class="btn-primary" type="submit">Cari</button>
    </form>

    <p v-if="notice" class="mb-3 rounded-xl bg-ok-bg p-3 text-sm text-ok-fg" role="status">{{ notice }}</p>
    <p v-if="error" class="rounded-xl bg-bad-bg p-3 text-sm text-bad-fg" role="alert">
      {{ error }} <button class="ml-2 font-semibold underline" type="button" @click="load">Coba lagi</button>
    </p>
    <div v-else-if="loading" class="h-40 animate-pulse rounded-xl bg-surface"></div>
    <p v-else-if="!items.length" class="rounded-xl bg-surface p-8 text-center text-sm text-muted">Belum ada produk untuk filter ini.</p>
    <div v-else class="w-full overflow-x-auto">
      <table class="w-full min-w-[760px] text-left text-sm">
        <thead class="text-xs text-muted">
          <tr><th class="p-3 font-medium">Produk</th><th class="p-3 font-medium">Kategori</th><th class="p-3 font-medium">UMKM</th><th class="p-3 font-medium">Harga</th><th class="p-3 font-medium">Stok</th><th class="p-3 font-medium">Status</th><th class="p-3"></th></tr>
        </thead>
        <tbody>
          <tr v-for="p in items" :key="p.id" class="border-t border-line">
            <td class="p-3">
              <div class="flex items-center gap-3">
                <span class="h-10 w-10 shrink-0 overflow-hidden rounded-[10px] bg-[#EDEDF0]"><img v-if="thumb(p)" :src="thumb(p)" alt="" class="h-full w-full object-cover" /></span>
                <b>{{ p.name }}</b>
              </div>
            </td>
            <td class="p-3">{{ p.categories?.name || '-' }}</td>
            <td class="p-3">{{ p.umkm?.name }}</td>
            <td class="p-3 font-bold text-gray-900">{{ formatRupiah(p.price) }}</td>
            <td class="p-3">
              {{ p.stock }}
              <span v-if="p.is_active && p.stock <= 10" class="badge ml-1 bg-warn-bg text-warn-fg">{{ p.stock === 0 ? 'Habis' : 'Menipis' }}</span>
            </td>
            <td class="p-3"><span class="badge" :class="p.is_active ? 'bg-ok-bg text-ok-fg' : 'bg-surface text-muted'">{{ p.is_active ? 'Aktif' : 'Nonaktif' }}</span></td>
            <td class="whitespace-nowrap p-3 text-right">
              <button class="rounded-lg border border-gray-900 px-3 py-2 font-semibold text-gray-900 transition hover:bg-gray-50" type="button" @click="lihatDetail(p)">Detail</button>
              <button
                v-if="p.is_active"
                class="ml-2 rounded-lg border border-gray-900 px-3 py-2 font-semibold text-gray-900 transition hover:bg-gray-50 disabled:cursor-wait disabled:opacity-50"
                type="button"
                :disabled="moderatingId === p.id"
                @click="toggle(p)"
              >{{ moderatingId === p.id ? 'Menonaktifkan...' : 'Nonaktifkan' }}</button>
              <span v-else class="ml-2 text-xs text-muted">Diblokir / nonaktif</span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <PaginationBar :page="num('page')" :total="total" @change="(p) => set({ page: p })" />
  </div>

  <ModalDialog :open="detailOpen" title="Detail Produk" @close="detailOpen = false">
    <div v-if="detailLoading" class="h-40 animate-pulse rounded-xl bg-surface"></div>
    <p v-else-if="detailError" class="rounded-xl bg-bad-bg p-3 text-sm text-bad-fg" role="alert">{{ detailError }}</p>
    <div v-else-if="detail" class="max-h-[70vh] space-y-4 overflow-y-auto">
      <div class="flex gap-3 overflow-x-auto">
        <img v-for="image in detailThumb(detail)" :key="image.id" :src="image.url" :alt="detail.name" class="h-24 w-24 shrink-0 rounded-lg bg-surface object-cover" />
        <div v-if="!detail.product_images?.length" class="flex h-24 w-24 shrink-0 items-center justify-center rounded-lg bg-surface text-xs text-muted">Tanpa foto</div>
      </div>
      <dl class="grid gap-3 text-sm sm:grid-cols-2">
        <div><dt class="text-muted">Nama produk</dt><dd class="mt-0.5 font-semibold">{{ detail.name }}</dd></div>
        <div><dt class="text-muted">UMKM</dt><dd class="mt-0.5 font-semibold">{{ detail.umkm?.name || '-' }}</dd></div>
        <div><dt class="text-muted">Kategori</dt><dd class="mt-0.5 font-semibold">{{ detail.categories?.name || '-' }}</dd></div>
        <div><dt class="text-muted">Slug</dt><dd class="mt-0.5 break-all font-semibold">{{ detail.slug }}</dd></div>
        <div><dt class="text-muted">Harga</dt><dd class="mt-0.5 font-bold text-gray-900">{{ formatRupiah(detail.price) }}</dd></div>
        <div><dt class="text-muted">Stok</dt><dd class="mt-0.5 font-semibold">{{ detail.stock }}</dd></div>
        <div><dt class="text-muted">Status</dt><dd class="mt-0.5 font-semibold">{{ detail.is_active ? 'Aktif' : 'Nonaktif' }}</dd></div>
        <div><dt class="text-muted">Dibuat</dt><dd class="mt-0.5 font-semibold">{{ formatTanggalJam(detail.created_at) }}</dd></div>
      </dl>
      <div><p class="text-sm text-muted">Deskripsi</p><p class="mt-1 whitespace-pre-wrap text-sm">{{ detail.description || 'Belum ada deskripsi.' }}</p></div>
      <div class="flex justify-end border-t border-line pt-3">
        <button class="btn-outline" type="button" @click="detailOpen = false">Tutup</button>
      </div>
    </div>
  </ModalDialog>
</template>
