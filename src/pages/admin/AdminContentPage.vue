<script setup>
import { reactive, ref } from 'vue'
import AdminPageHeader from '@/components/AdminPageHeader.vue'
import ModalDialog from '@/components/ModalDialog.vue'
import { formatTanggal } from '@/lib/format'

const banners = ref([
  { id: 1, title: 'Promo Kemerdekaan UMKM', subtitle: 'Rayakan produk lokal, hemat hingga 25%', placement: 'Beranda · Slider utama', start: '2026-08-01', end: '2026-08-31', active: false, theme: 'bg-gray-900 text-white' },
  { id: 2, title: 'Diskon Spesial Kerajinan', subtitle: 'Temukan karya tangan pilihan dari pengrajin lokal', placement: 'Beranda · Slider utama', start: '2026-10-01', end: '2026-10-31', active: true, theme: 'bg-gray-800 text-white' },
  { id: 3, title: 'Rasa Nusantara di Rumah', subtitle: 'Produk pangan dan rempah unggulan dari UMKM', placement: 'Katalog · Banner kategori', start: '2026-10-15', end: '2026-11-15', active: true, theme: 'bg-gray-100 text-gray-900' },
])
const editingBanner = ref(null)
const notice = ref('')
const form = reactive({ title: '', subtitle: '', placement: '', start: '', end: '' })

function openEditor(banner) {
  editingBanner.value = banner
  Object.assign(form, {
    title: banner.title,
    subtitle: banner.subtitle,
    placement: banner.placement,
    start: banner.start,
    end: banner.end,
  })
}

function saveBanner() {
  const banner = editingBanner.value
  if (!banner) return
  Object.assign(banner, {
    title: form.title.trim(),
    subtitle: form.subtitle.trim(),
    placement: form.placement.trim(),
    start: form.start,
    end: form.end,
  })
  editingBanner.value = null
  notice.value = 'Banner berhasil diperbarui.'
}

function deleteBanner(banner) {
  if (!confirm(`Hapus banner "${banner.title}"?`)) return
  banners.value = banners.value.filter((item) => item.id !== banner.id)
  notice.value = 'Banner berhasil dihapus.'
}
</script>

<template>
  <AdminPageHeader title="Manajemen Konten" desc="Pratinjau dan kelola materi promosi marketplace." />

  <p v-if="notice" class="mb-4 rounded-xl border border-gray-200 bg-white p-3 text-sm text-gray-800" role="status">{{ notice }}</p>

  <section class="grid gap-4 xl:grid-cols-2" aria-label="Daftar banner promosi">
    <article v-for="banner in banners" :key="banner.id" class="card overflow-hidden">
      <div class="p-5">
        <div class="flex items-start justify-between gap-3">
          <span class="badge" :class="banner.active ? 'bg-gray-900 text-white' : 'bg-gray-100 text-gray-700'">{{ banner.active ? 'Aktif' : 'Terjadwal' }}</span>
          <span class="text-xs font-medium text-gray-500">{{ banner.placement }}</span>
        </div>
        <div class="mt-4 flex min-h-40 flex-col justify-between rounded-xl p-5 sm:min-h-44" :class="banner.theme">
          <span class="text-xs font-semibold uppercase tracking-[0.18em] opacity-75">PasarPintar · Pilihan Lokal</span>
          <div class="mt-6">
            <h2 class="max-w-md text-2xl font-bold tracking-tight">{{ banner.title }}</h2>
            <p class="mt-2 max-w-md text-sm opacity-80">{{ banner.subtitle }}</p>
          </div>
        </div>
        <div class="mt-4 flex flex-wrap items-center justify-between gap-3">
          <p class="text-sm text-gray-600">
            Periode <time :datetime="banner.start">{{ formatTanggal(banner.start) }}</time>
            <span aria-hidden="true">–</span>
            <time :datetime="banner.end">{{ formatTanggal(banner.end) }}</time>
          </p>
          <div class="flex gap-2">
            <button class="btn-outline !min-h-10 !px-4" type="button" @click="openEditor(banner)">Edit</button>
            <button class="btn-outline !min-h-10 !px-4" type="button" @click="deleteBanner(banner)">Hapus</button>
          </div>
        </div>
      </div>
    </article>
    <p v-if="!banners.length" class="card p-8 text-center text-sm text-gray-600 xl:col-span-2">Belum ada banner promosi.</p>
  </section>

  <ModalDialog :open="!!editingBanner" title="Edit banner" @close="editingBanner = null">
    <form class="space-y-4" @submit.prevent="saveBanner">
      <div>
        <label for="banner-title" class="mb-1.5 block text-sm font-medium text-gray-700">Judul banner</label>
        <input id="banner-title" v-model="form.title" class="input" required maxlength="80" />
      </div>
      <div>
        <label for="banner-subtitle" class="mb-1.5 block text-sm font-medium text-gray-700">Deskripsi singkat</label>
        <textarea id="banner-subtitle" v-model="form.subtitle" class="input min-h-24 py-3" required maxlength="140"></textarea>
      </div>
      <div>
        <label for="banner-placement" class="mb-1.5 block text-sm font-medium text-gray-700">Penempatan</label>
        <input id="banner-placement" v-model="form.placement" class="input" required maxlength="60" />
      </div>
      <div class="grid gap-3 sm:grid-cols-2">
        <div>
          <label for="banner-start" class="mb-1.5 block text-sm font-medium text-gray-700">Mulai</label>
          <input id="banner-start" v-model="form.start" class="input" type="date" required />
        </div>
        <div>
          <label for="banner-end" class="mb-1.5 block text-sm font-medium text-gray-700">Berakhir</label>
          <input id="banner-end" v-model="form.end" class="input" type="date" required />
        </div>
      </div>
      <div class="flex justify-end gap-2 pt-2">
        <button class="btn-outline" type="button" @click="editingBanner = null">Batal</button>
        <button class="btn-primary" type="submit">Simpan perubahan</button>
      </div>
    </form>
  </ModalDialog>
</template>
