<script setup>
import { computed, onBeforeUnmount, onMounted, reactive, ref } from 'vue'
import SellerDashboardSidebar from '@/components/SellerDashboardSidebar.vue'
import { getMyUmkm } from '@/services/umkmPartnerService'
import { listRegions } from '@/services/adminCatalogService'
import { deleteStoreAsset, getStoreSettings, saveStoreSettings, uploadStoreAsset } from '@/services/sellerStoreSettingsService'

const tabs = [
  { id: 'profile', label: 'Profil Toko' },
  { id: 'location', label: 'Lokasi & Pengiriman' },
  { id: 'bank', label: 'Rekening Bank' },
  { id: 'hours', label: 'Jam Operasional' },
]
const couriers = ['JNE', 'POS Indonesia', 'TIKI', 'SiCepat', 'J&T Express', 'AnterAja']
const days = [
  { id: 'monday', label: 'Senin' },
  { id: 'tuesday', label: 'Selasa' },
  { id: 'wednesday', label: 'Rabu' },
  { id: 'thursday', label: 'Kamis' },
  { id: 'friday', label: 'Jumat' },
  { id: 'saturday', label: 'Sabtu' },
  { id: 'sunday', label: 'Minggu' },
]
const defaultHours = () => Object.fromEntries(days.map(({ id }) => [id, {
  enabled: !['saturday', 'sunday'].includes(id),
  open: '08:00',
  close: '17:00',
}]))

const umkm = ref(null)
const regions = ref([])
const loading = ref(true)
const saving = ref(false)
const error = ref('')
const notice = ref('')
const warning = ref('')
const activeTab = ref('profile')
const selectedProvince = ref('')
const logoFile = ref(null)
const bannerFile = ref(null)
const logoPreview = ref('')
const bannerPreview = ref('')
const form = reactive({
  name: '',
  tagline: '',
  description: '',
  address: '',
  region_id: '',
  logo_url: '',
  banner_url: '',
  shipping_providers: [],
  bank_name: '',
  bank_account_number: '',
  bank_account_holder: '',
  opening_hours: defaultHours(),
})

const provinces = computed(() => [...new Set(regions.value.map((region) => region.province))].sort((a, b) => a.localeCompare(b, 'id')))
const availableCities = computed(() => regions.value
  .filter((region) => region.province === selectedProvince.value)
  .sort((a, b) => a.name.localeCompare(b.name, 'id')))
const canManageSettings = computed(() => umkm.value?.status === 'active' && umkm.value.is_active)
const currentRegion = computed(() => regions.value.find((region) => region.id === form.region_id))

function setImagePreview(kind, file) {
  const fileRef = kind === 'logo' ? logoFile : bannerFile
  const previewRef = kind === 'logo' ? logoPreview : bannerPreview
  if (previewRef.value) URL.revokeObjectURL(previewRef.value)
  fileRef.value = file
  previewRef.value = file ? URL.createObjectURL(file) : ''
}

function pilihGambar(kind, event) {
  error.value = ''
  const file = event.target.files?.[0] ?? null
  if (file && !['image/jpeg', 'image/png', 'image/webp'].includes(file.type)) {
    error.value = 'Format gambar harus JPG, PNG, atau WebP.'
    event.target.value = ''
    return
  }
  if (file && file.size > 4 * 1024 * 1024) {
    error.value = 'Ukuran gambar maksimal 4 MB.'
    event.target.value = ''
    return
  }
  setImagePreview(kind, file)
  event.target.value = ''
}

function hapusGambar(kind) {
  setImagePreview(kind, null)
  if (kind === 'logo') form.logo_url = ''
  else form.banner_url = ''
}

async function load() {
  loading.value = true
  error.value = ''
  try {
    const [application, allRegions] = await Promise.all([getMyUmkm(), listRegions()])
    umkm.value = application
    regions.value = allRegions
    if (!application || application.status !== 'active' || !application.is_active) return

    const settings = await getStoreSettings(application.id)
    Object.assign(form, {
      name: settings.name ?? '',
      tagline: settings.tagline ?? '',
      description: settings.description ?? '',
      address: settings.address ?? '',
      region_id: settings.region_id ?? '',
      logo_url: settings.logo_url ?? '',
      banner_url: settings.banner_url ?? '',
      shipping_providers: settings.shipping_providers ?? [],
      bank_name: settings.bank_name ?? '',
      bank_account_number: settings.bank_account_number ?? '',
      bank_account_holder: settings.bank_account_holder ?? '',
      opening_hours: Object.fromEntries(days.map(({ id }) => [
        id,
        { ...defaultHours()[id], ...(settings.opening_hours?.[id] ?? {}) },
      ])),
    })
    selectedProvince.value = regions.value.find((region) => region.id === form.region_id)?.province ?? ''
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

onMounted(load)
onBeforeUnmount(() => {
  if (logoPreview.value) URL.revokeObjectURL(logoPreview.value)
  if (bannerPreview.value) URL.revokeObjectURL(bannerPreview.value)
})

function pilihProvinsi() {
  form.region_id = ''
}

function toggleKurir(courier) {
  form.shipping_providers = form.shipping_providers.includes(courier)
    ? form.shipping_providers.filter((item) => item !== courier)
    : [...form.shipping_providers, courier]
}

async function simpanPerubahan() {
  if (!canManageSettings.value) return
  saving.value = true
  error.value = ''
  notice.value = ''
  warning.value = ''
  let newLogoUrl = ''
  let newBannerUrl = ''
  const previousLogo = form.logo_url
  const previousBanner = form.banner_url

  try {
    if (!form.name.trim()) throw new Error('Nama UMKM wajib diisi.')
    if (logoFile.value) newLogoUrl = await uploadStoreAsset(umkm.value.id, logoFile.value)
    if (bannerFile.value) newBannerUrl = await uploadStoreAsset(umkm.value.id, bannerFile.value)

    const payload = {
      ...form,
      name: form.name.trim(),
      tagline: form.tagline.trim(),
      description: form.description.trim(),
      address: form.address.trim(),
      region_id: form.region_id || null,
      logo_url: newLogoUrl || form.logo_url || null,
      banner_url: newBannerUrl || form.banner_url || null,
      shipping_providers: [...form.shipping_providers],
      bank_name: form.bank_name.trim(),
      bank_account_number: form.bank_account_number.trim(),
      bank_account_holder: form.bank_account_holder.trim(),
      opening_hours: JSON.parse(JSON.stringify(form.opening_hours)),
    }

    await saveStoreSettings(umkm.value.id, payload)
    form.logo_url = payload.logo_url ?? ''
    form.banner_url = payload.banner_url ?? ''
    setImagePreview('logo', null)
    setImagePreview('banner', null)
    notice.value = 'Pengaturan toko berhasil disimpan.'

    try {
      if (previousLogo && previousLogo !== payload.logo_url) await deleteStoreAsset(previousLogo)
      if (previousBanner && previousBanner !== payload.banner_url) await deleteStoreAsset(previousBanner)
    } catch (cleanupError) {
      warning.value = `Pengaturan tersimpan, tetapi gambar lama gagal dibersihkan: ${cleanupError.message}`
    }
  } catch (e) {
    error.value = e.message
    for (const url of [newLogoUrl, newBannerUrl]) {
      if (url) {
        try {
          await deleteStoreAsset(url)
        } catch (cleanupError) {
          warning.value = `Gambar baru gagal dibersihkan setelah penyimpanan gagal: ${cleanupError.message}`
        }
      }
    }
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div class="min-h-full bg-slate-50 lg:flex">
    <SellerDashboardSidebar :umkm="umkm" />

    <main class="min-w-0 flex-1 px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
      <div class="mx-auto max-w-6xl">
        <div class="mb-6">
          <p class="text-sm font-medium text-emerald-700">Seller Centre</p>
          <h1 class="mt-1 text-2xl font-bold tracking-tight text-slate-900 sm:text-3xl">Pengaturan Toko</h1>
          <p class="mt-1.5 text-sm text-slate-500">Kelola profil, pengiriman, rekening, dan jam operasional toko Anda.</p>
        </div>

        <p v-if="notice" class="mb-4 rounded-xl border border-emerald-100 bg-emerald-50 p-3 text-sm text-emerald-800" role="status">{{ notice }}</p>
        <p v-if="error" class="mb-4 rounded-xl border border-red-100 bg-red-50 p-3 text-sm text-red-700" role="alert">{{ error }}</p>
        <p v-if="warning" class="mb-4 rounded-xl border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900" role="status">{{ warning }}</p>

        <div v-if="loading" class="h-96 animate-pulse rounded-xl bg-white shadow-sm ring-1 ring-slate-200"></div>
        <div v-else-if="!umkm" class="rounded-xl border border-slate-200 bg-white p-6">
          <p class="font-semibold text-slate-900">Data UMKM tidak ditemukan.</p>
        </div>
        <div v-else-if="!canManageSettings" class="rounded-xl border border-amber-200 bg-amber-50 p-5 text-sm text-amber-900" role="status">
          Pengaturan toko tersedia setelah pendaftaran UMKM disetujui dan toko diaktifkan.
        </div>
        <form v-else class="overflow-hidden rounded-xl bg-white shadow-sm ring-1 ring-slate-200" @submit.prevent="simpanPerubahan">
          <nav class="flex gap-1 overflow-x-auto border-b border-slate-200 px-4 pt-3 sm:px-6" aria-label="Tab pengaturan toko">
            <button
              v-for="tab in tabs"
              :key="tab.id"
              class="whitespace-nowrap border-b-2 px-3 py-3 text-sm font-medium transition"
              :class="activeTab === tab.id ? 'border-gray-900 text-gray-900' : 'border-transparent text-slate-500 hover:text-slate-800'"
              type="button"
              :aria-current="activeTab === tab.id ? 'page' : undefined"
              @click="activeTab = tab.id"
            >{{ tab.label }}</button>
          </nav>

          <div class="min-h-[480px] p-5 sm:p-7">
            <section v-if="activeTab === 'profile'" class="space-y-6">
              <div>
                <h2 class="font-semibold text-slate-900">Profil Toko</h2>
                <p class="mt-1 text-sm text-slate-500">Informasi yang akan dilihat pelanggan di halaman toko.</p>
              </div>
              <div class="grid gap-6 lg:grid-cols-[220px_minmax(0,1fr)]">
                <div>
                  <p class="mb-2 text-sm font-medium text-slate-700">Logo Toko</p>
                  <label class="group relative flex h-36 w-36 cursor-pointer items-center justify-center overflow-hidden rounded-full border-2 border-dashed border-slate-300 bg-slate-50 text-center transition hover:border-gray-900 hover:bg-gray-50">
                    <img v-if="logoPreview || form.logo_url" :src="logoPreview || form.logo_url" alt="Pratinjau logo toko" class="h-full w-full object-cover" />
                    <span v-else class="px-4 text-xs leading-5 text-slate-500">Klik untuk unggah logo</span>
                    <input class="sr-only" type="file" accept="image/png,image/jpeg,image/webp" @change="pilihGambar('logo', $event)" />
                  </label>
                  <button v-if="logoPreview || form.logo_url" class="mt-2 text-xs font-medium text-gray-900 hover:underline" type="button" @click="hapusGambar('logo')">Hapus logo</button>
                  <p class="mt-2 text-xs text-slate-500">JPG, PNG, WebP · maks. 4 MB</p>
                </div>
                <div>
                  <p class="mb-2 text-sm font-medium text-slate-700">Banner Toko</p>
                  <label class="group relative flex aspect-[3/1] w-full cursor-pointer items-center justify-center overflow-hidden rounded-xl border-2 border-dashed border-slate-300 bg-slate-50 text-center transition hover:border-gray-900 hover:bg-gray-50">
                    <img v-if="bannerPreview || form.banner_url" :src="bannerPreview || form.banner_url" alt="Pratinjau banner toko" class="absolute inset-0 h-full w-full object-cover" />
                    <span v-else class="px-4 text-sm text-slate-500">Klik untuk unggah banner toko</span>
                    <input class="sr-only" type="file" accept="image/png,image/jpeg,image/webp" @change="pilihGambar('banner', $event)" />
                  </label>
                  <button v-if="bannerPreview || form.banner_url" class="mt-2 text-xs font-medium text-gray-900 hover:underline" type="button" @click="hapusGambar('banner')">Hapus banner</button>
                  <p class="mt-2 text-xs text-slate-500">Saran rasio 3:1 · JPG, PNG, WebP · maks. 4 MB</p>
                </div>
              </div>
              <div class="grid gap-4">
                <label class="block text-sm font-medium text-slate-700">Nama UMKM
                  <input v-model="form.name" class="input mt-1.5 w-full" maxlength="120" required />
                </label>
                <label class="block text-sm font-medium text-slate-700">Slogan pendek
                  <input v-model="form.tagline" class="input mt-1.5 w-full" maxlength="160" placeholder="Tulis slogan toko" />
                </label>
                <label class="block text-sm font-medium text-slate-700">Deskripsi toko
                  <textarea v-model="form.description" class="input mt-1.5 w-full py-2" rows="4" maxlength="2000" placeholder="Ceritakan produk dan keunikan toko Anda"></textarea>
                </label>
              </div>
            </section>

            <section v-else-if="activeTab === 'location'" class="space-y-6">
              <div>
                <h2 class="font-semibold text-slate-900">Lokasi & Pengiriman</h2>
                <p class="mt-1 text-sm text-slate-500">Atur lokasi toko dan jasa kurir yang tersedia.</p>
              </div>
              <label class="block text-sm font-medium text-slate-700">Alamat Lengkap
                <textarea v-model="form.address" class="input mt-1.5 w-full py-2" rows="3" maxlength="1000" placeholder="Nama jalan, nomor, kelurahan, kecamatan"></textarea>
              </label>
              <div class="grid gap-4 sm:grid-cols-2">
                <label class="block text-sm font-medium text-slate-700">Provinsi
                  <select v-model="selectedProvince" class="input mt-1.5 w-full" @change="pilihProvinsi">
                    <option value="">Pilih provinsi</option>
                    <option v-for="province in provinces" :key="province" :value="province">{{ province }}</option>
                  </select>
                </label>
                <label class="block text-sm font-medium text-slate-700">Kota / Kabupaten
                  <select v-model="form.region_id" class="input mt-1.5 w-full" :disabled="!selectedProvince">
                    <option value="">Pilih kota/kabupaten</option>
                    <option v-for="region in availableCities" :key="region.id" :value="region.id">{{ region.name }}</option>
                  </select>
                </label>
              </div>
              <div>
                <h3 class="text-sm font-semibold text-slate-800">Jasa kurir yang diaktifkan</h3>
                <div class="mt-3 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                  <label v-for="courier in couriers" :key="courier" class="flex cursor-pointer items-center gap-3 rounded-lg border border-slate-200 p-3 text-sm text-slate-700 hover:border-gray-300">
                    <input :checked="form.shipping_providers.includes(courier)" class="h-4 w-4 rounded border-slate-300 text-gray-900 focus:ring-gray-900 accent-gray-900" type="checkbox" @change="toggleKurir(courier)" />
                    {{ courier }}
                  </label>
                </div>
              </div>
            </section>

            <section v-else-if="activeTab === 'bank'" class="max-w-2xl space-y-6">
              <div>
                <h2 class="font-semibold text-slate-900">Rekening Bank</h2>
                <p class="mt-1 text-sm text-slate-500">Rekening ini digunakan untuk pencairan dana penjualan.</p>
              </div>
              <div class="rounded-lg border border-sky-100 bg-sky-50 p-4 text-sm leading-6 text-sky-900">
                Pastikan nama pemilik dan nomor rekening sesuai dengan data bank agar pencairan dana dapat diproses dengan lancar.
              </div>
              <label class="block text-sm font-medium text-slate-700">Nama Bank
                <select v-model="form.bank_name" class="input mt-1.5 w-full">
                  <option value="">Pilih bank</option>
                  <option v-for="bank in ['BCA', 'Bank Mandiri', 'BRI', 'BNI', 'BSI', 'Bank lainnya']" :key="bank" :value="bank">{{ bank }}</option>
                </select>
              </label>
              <label class="block text-sm font-medium text-slate-700">Nomor Rekening
                <input v-model="form.bank_account_number" class="input mt-1.5 w-full" inputmode="numeric" maxlength="40" autocomplete="off" />
              </label>
              <label class="block text-sm font-medium text-slate-700">Nama Pemilik Rekening
                <input v-model="form.bank_account_holder" class="input mt-1.5 w-full" maxlength="120" autocomplete="name" />
              </label>
              <p class="text-xs text-slate-500">Informasi rekening hanya dapat dibaca melalui layanan pengaturan oleh pemilik toko.</p>
            </section>

            <section v-else class="space-y-6">
              <div>
                <h2 class="font-semibold text-slate-900">Jam Operasional</h2>
                <p class="mt-1 text-sm text-slate-500">Tentukan hari dan jam toko melayani pelanggan.</p>
              </div>
              <div class="divide-y divide-slate-100 rounded-xl border border-slate-200">
                <div v-for="day in days" :key="day.id" class="grid gap-3 p-4 sm:grid-cols-[120px_1fr_1fr] sm:items-center">
                  <label class="flex items-center gap-2.5 text-sm font-medium text-slate-800">
                    <input v-model="form.opening_hours[day.id].enabled" class="h-4 w-4 rounded border-slate-300 text-gray-900 focus:ring-gray-900 accent-gray-900" type="checkbox" />
                    {{ day.label }}
                  </label>
                  <label class="text-xs text-slate-500">Buka
                    <input v-model="form.opening_hours[day.id].open" class="input mt-1 w-full" type="time" :disabled="!form.opening_hours[day.id].enabled" />
                  </label>
                  <label class="text-xs text-slate-500">Tutup
                    <input v-model="form.opening_hours[day.id].close" class="input mt-1 w-full" type="time" :disabled="!form.opening_hours[day.id].enabled" />
                  </label>
                </div>
              </div>
            </section>
          </div>

          <div class="sticky bottom-0 flex flex-wrap items-center justify-between gap-3 border-t border-slate-200 bg-white/95 px-5 py-4 backdrop-blur sm:px-7">
            <p v-if="currentRegion" class="text-xs text-slate-500">Lokasi toko: {{ currentRegion.name }}, {{ currentRegion.province }}</p>
            <span v-else class="text-xs text-slate-500">Perubahan berlaku setelah disimpan.</span>
            <button class="inline-flex min-h-11 items-center justify-center rounded-lg bg-gray-900 px-5 text-sm font-semibold text-white transition hover:bg-black disabled:cursor-wait disabled:opacity-60" type="submit" :disabled="saving">
              {{ saving ? 'Menyimpan...' : 'Simpan Perubahan' }}
            </button>
          </div>
        </form>
      </div>
    </main>
  </div>
</template>
