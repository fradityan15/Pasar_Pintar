<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
import AdminPageHeader from '@/components/AdminPageHeader.vue'
import ModalDialog from '@/components/ModalDialog.vue'
import { formatRupiah, formatTanggalJam } from '@/lib/format'
import {
  deleteVoucher,
  listVoucherClaimReport,
  listVouchersAdmin,
  listVoucherScopeOptions,
  saveVoucher,
} from '@/services/voucherService'

const vouchers = ref([])
const claims = ref([])
const stores = ref([])
const categories = ref([])
const loading = ref(true)
const saving = ref(false)
const open = ref(false)
const editingId = ref('')
const error = ref('')
const formError = ref('')
const notice = ref('')
const form = reactive({
  code: '',
  discount_type: 'nominal',
  discount_value: '',
  maximum_discount: '',
  minimum_purchase: 0,
  quota_total: '',
  berlaku_dari: '',
  berlaku_sampai: '',
  is_active: false,
  scope_type: 'all',
  umkm_ids: [],
  category_ids: [],
})

const usedCount = computed(() => claims.value.filter((claim) => claim.status === 'used').length)
const claimedCount = computed(() => claims.value.filter((claim) => claim.status === 'claimed').length)

async function load() {
  loading.value = true
  error.value = ''
  try {
    const [voucherRows, claimRows, scopeOptions] = await Promise.all([
      listVouchersAdmin(),
      listVoucherClaimReport(),
      listVoucherScopeOptions(),
    ])
    vouchers.value = voucherRows ?? []
    claims.value = claimRows ?? []
    stores.value = scopeOptions.stores
    categories.value = scopeOptions.categories
  } catch (loadError) {
    error.value = loadError.message || 'Data voucher tidak dapat dimuat.'
  } finally {
    loading.value = false
  }
}

onMounted(load)

function localDateTime(value) {
  if (!value) return ''
  const date = new Date(value)
  date.setMinutes(date.getMinutes() - date.getTimezoneOffset())
  return date.toISOString().slice(0, 16)
}

function openForm(voucher = null) {
  editingId.value = voucher?.id ?? ''
  Object.assign(form, {
    code: voucher?.code ?? '',
    discount_type: voucher?.discount_type ?? 'nominal',
    discount_value: voucher?.discount_value ?? '',
    maximum_discount: voucher?.maximum_discount ?? '',
    minimum_purchase: voucher?.minimum_purchase ?? 0,
    quota_total: voucher?.quota_total ?? '',
    berlaku_dari: localDateTime(voucher?.berlaku_dari),
    berlaku_sampai: localDateTime(voucher?.berlaku_sampai),
    is_active: voucher?.is_active ?? false,
    scope_type: voucher?.scope_type ?? 'all',
    umkm_ids: [...(voucher?.umkm_ids ?? [])],
    category_ids: [...(voucher?.category_ids ?? [])],
  })
  formError.value = ''
  open.value = true
}

async function save() {
  saving.value = true
  formError.value = ''
  try {
    if (!form.berlaku_dari || !form.berlaku_sampai) {
      throw new Error('Tanggal mulai dan berakhir wajib diisi.')
    }
    if (form.scope_type === 'stores' && !form.umkm_ids.length) {
      throw new Error('Pilih setidaknya satu toko untuk cakupan voucher.')
    }
    if (form.scope_type === 'categories' && !form.category_ids.length) {
      throw new Error('Pilih setidaknya satu kategori untuk cakupan voucher.')
    }
    const startsAt = new Date(form.berlaku_dari)
    const endsAt = new Date(form.berlaku_sampai)
    if (Number.isNaN(startsAt.getTime()) || Number.isNaN(endsAt.getTime()) || endsAt <= startsAt) {
      throw new Error('Rentang tanggal voucher tidak valid.')
    }
    await saveVoucher(editingId.value || null, {
      code: form.code.trim().toUpperCase(),
      discount_type: form.discount_type,
      discount_value: Number(form.discount_value),
      maximum_discount: form.maximum_discount === '' ? null : Number(form.maximum_discount),
      minimum_purchase: Number(form.minimum_purchase),
      quota_total: form.quota_total === '' ? null : Number(form.quota_total),
      berlaku_dari: startsAt.toISOString(),
      berlaku_sampai: endsAt.toISOString(),
      is_active: form.is_active,
      scope_type: form.scope_type,
      umkm_ids: form.scope_type === 'stores' ? form.umkm_ids : [],
      category_ids: form.scope_type === 'categories' ? form.category_ids : [],
    })
    open.value = false
    notice.value = 'Voucher berhasil disimpan.'
    await load()
  } catch (saveError) {
    formError.value = saveError.message || 'Voucher tidak dapat disimpan.'
  } finally {
    saving.value = false
  }
}

async function remove(voucher) {
  if (!confirm(`Hapus voucher ${voucher.code}? Voucher yang sudah memiliki klaim tidak dapat dihapus.`)) return
  error.value = ''
  notice.value = ''
  try {
    await deleteVoucher(voucher.id)
    notice.value = `Voucher ${voucher.code} dihapus.`
    await load()
  } catch (deleteError) {
    error.value = deleteError.message || 'Voucher tidak dapat dihapus.'
  }
}

function scopeLabel(voucher) {
  if (voucher.scope_type === 'stores') {
    return voucher.umkm_ids.map((id) => stores.value.find((store) => store.id === id)?.name ?? id).join(', ')
  }
  if (voucher.scope_type === 'categories') {
    return voucher.category_ids.map((id) => categories.value.find((category) => category.id === id)?.name ?? id).join(', ')
  }
  return 'Semua toko'
}

function discountLabel(voucher) {
  return voucher.discount_type === 'persen'
    ? `${voucher.discount_value}%${voucher.maximum_discount != null ? ` · maks ${formatRupiah(voucher.maximum_discount)}` : ''}`
    : formatRupiah(voucher.discount_value)
}
</script>

<template>
  <AdminPageHeader title="Voucher GBBI" desc="Atur parameter program sesuai ketentuan resmi yang sudah dikonfirmasi.">
    <button class="btn-primary" type="button" @click="openForm()">Tambah voucher</button>
  </AdminPageHeader>

  <p class="mb-5 rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">
    Kebijakan nominal subsidi, periode, kuota, minimal belanja, dan cakupan belum ditentukan di aplikasi. Pastikan seluruh nilai mengikuti persetujuan program sebelum mengaktifkan voucher.
  </p>
  <p v-if="notice" class="mb-4 rounded-xl bg-ok-bg p-3 text-sm text-ok-fg" role="status">{{ notice }}</p>
  <p v-if="error" class="mb-4 rounded-xl bg-bad-bg p-3 text-sm text-bad-fg" role="alert">{{ error }}</p>

  <section class="mb-6 grid gap-4 sm:grid-cols-2">
    <article class="card p-5"><p class="text-sm text-muted">Klaim aktif · 500 terbaru</p><p class="mt-2 text-2xl font-bold">{{ claimedCount }}</p></article>
    <article class="card p-5"><p class="text-sm text-muted">Klaim terpakai · 500 terbaru</p><p class="mt-2 text-2xl font-bold">{{ usedCount }}</p></article>
  </section>

  <section class="card overflow-hidden">
    <div class="flex items-center justify-between border-b border-line px-5 py-4">
      <h2 class="font-semibold">Daftar voucher dan pemakaian</h2>
      <button class="btn-outline" type="button" :disabled="loading" @click="load">Muat ulang</button>
    </div>
    <div v-if="loading" class="p-6 text-sm text-muted">Memuat voucher…</div>
    <div v-else-if="!vouchers.length" class="p-6 text-sm text-muted">Belum ada voucher.</div>
    <div v-else class="overflow-x-auto">
      <table class="w-full min-w-[980px] text-left text-sm">
        <thead class="bg-gray-50 text-xs text-muted">
          <tr>
            <th class="px-4 py-3">Kode / Diskon</th><th class="px-4 py-3">Cakupan</th>
            <th class="px-4 py-3">Kuota</th><th class="px-4 py-3">Periode</th>
            <th class="px-4 py-3">Status</th><th class="px-4 py-3"></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="voucher in vouchers" :key="voucher.id" class="border-t border-line align-top">
            <td class="px-4 py-4">
              <p class="font-semibold">{{ voucher.code }}</p>
              <p class="mt-1 text-xs text-muted">{{ discountLabel(voucher) }} · min. {{ formatRupiah(voucher.minimum_purchase) }}</p>
            </td>
            <td class="max-w-64 whitespace-normal px-4 py-4 text-muted">{{ scopeLabel(voucher) }}</td>
            <td class="px-4 py-4">{{ voucher.quota_used }} / {{ voucher.quota_total ?? 'tanpa batas' }}</td>
            <td class="whitespace-nowrap px-4 py-4 text-xs text-muted">
              <p>{{ formatTanggalJam(voucher.berlaku_dari) }}</p><p class="mt-1">s.d. {{ formatTanggalJam(voucher.berlaku_sampai) }}</p>
            </td>
            <td class="px-4 py-4"><span class="badge" :class="voucher.is_active ? 'bg-ok-bg text-ok-fg' : 'bg-surface text-muted'">{{ voucher.is_active ? 'Aktif' : 'Nonaktif' }}</span></td>
            <td class="whitespace-nowrap px-4 py-4 text-right">
              <button class="font-semibold underline" type="button" @click="openForm(voucher)">Ubah</button>
              <button class="ml-3 font-semibold text-red-700 underline" type="button" @click="remove(voucher)">Hapus</button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </section>

  <section class="card mt-6 overflow-hidden">
    <div class="border-b border-line px-5 py-4"><h2 class="font-semibold">Laporan klaim dan pemakaian</h2><p class="mt-1 text-sm text-muted">Maksimal 500 klaim terbaru.</p></div>
    <div v-if="!claims.length" class="p-6 text-sm text-muted">Belum ada klaim.</div>
    <div v-else class="overflow-x-auto">
      <table class="w-full min-w-[760px] text-left text-sm">
        <thead class="bg-gray-50 text-xs text-muted"><tr><th class="px-4 py-3">Voucher</th><th class="px-4 py-3">Pengguna</th><th class="px-4 py-3">Status</th><th class="px-4 py-3">Diklaim</th><th class="px-4 py-3">Pesanan</th></tr></thead>
        <tbody>
          <tr v-for="claim in claims" :key="claim.id" class="border-t border-line">
            <td class="px-4 py-3 font-semibold">{{ claim.vouchers.code }}</td>
            <td class="px-4 py-3">{{ claim.profiles?.full_name || claim.user_id }}</td>
            <td class="px-4 py-3">{{ claim.status }}</td>
            <td class="whitespace-nowrap px-4 py-3">{{ formatTanggalJam(claim.claimed_at) }}</td>
            <td class="px-4 py-3 font-mono text-xs">{{ claim.order_id || 'Belum dipakai' }}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </section>

  <ModalDialog :open="open" :title="editingId ? 'Ubah voucher' : 'Tambah voucher'" @close="open = false">
    <form class="grid gap-3 sm:grid-cols-2" @submit.prevent="save">
      <label class="text-sm font-medium sm:col-span-2">Kode
        <input v-model="form.code" class="input mt-1 w-full uppercase" required maxlength="80" pattern="[A-Za-z0-9_-]+" />
      </label>
      <label class="text-sm font-medium">Tipe diskon
        <select v-model="form.discount_type" class="input mt-1 w-full"><option value="nominal">Nominal (Rp)</option><option value="persen">Persentase (%)</option></select>
      </label>
      <label class="text-sm font-medium">Nilai diskon
        <input v-model.number="form.discount_value" class="input mt-1 w-full" type="number" min="0.01" :max="form.discount_type === 'persen' ? 100 : undefined" :step="form.discount_type === 'persen' ? 0.01 : 1" required />
      </label>
      <label v-if="form.discount_type === 'persen'" class="text-sm font-medium">Maksimum potongan (kosong = tanpa batas)
        <input v-model.number="form.maximum_discount" class="input mt-1 w-full" type="number" min="0" step="1" />
      </label>
      <label class="text-sm font-medium">Minimal belanja (Rp)
        <input v-model.number="form.minimum_purchase" class="input mt-1 w-full" type="number" min="0" step="1" required />
      </label>
      <label class="text-sm font-medium">Kuota total (kosong = tanpa batas)
        <input v-model.number="form.quota_total" class="input mt-1 w-full" type="number" min="0" step="1" />
      </label>
      <label class="text-sm font-medium">Berlaku dari
        <input v-model="form.berlaku_dari" class="input mt-1 w-full" type="datetime-local" required />
      </label>
      <label class="text-sm font-medium">Berlaku sampai
        <input v-model="form.berlaku_sampai" class="input mt-1 w-full" type="datetime-local" required />
      </label>
      <label class="text-sm font-medium sm:col-span-2">Cakupan
        <select v-model="form.scope_type" class="input mt-1 w-full"><option value="all">Semua toko</option><option value="stores">Toko tertentu</option><option value="categories">Kategori tertentu</option></select>
      </label>
      <label v-if="form.scope_type === 'stores'" class="text-sm font-medium sm:col-span-2">Toko yang memenuhi syarat
        <select v-model="form.umkm_ids" class="input mt-1 w-full" multiple size="5" required>
          <option v-for="store in stores" :key="store.id" :value="store.id">{{ store.name }}</option>
        </select>
      </label>
      <label v-if="form.scope_type === 'categories'" class="text-sm font-medium sm:col-span-2">Kategori yang memenuhi syarat
        <select v-model="form.category_ids" class="input mt-1 w-full" multiple size="5" required>
          <option v-for="category in categories" :key="category.id" :value="category.id">{{ category.name }}</option>
        </select>
      </label>
      <label class="flex items-center gap-2 text-sm sm:col-span-2"><input v-model="form.is_active" type="checkbox" /> Aktifkan sesuai ketentuan program</label>
      <p v-if="formError" class="rounded-xl bg-bad-bg p-3 text-sm text-bad-fg sm:col-span-2" role="alert">{{ formError }}</p>
      <div class="flex justify-end gap-2 sm:col-span-2">
        <button class="btn-outline" type="button" @click="open = false">Batal</button>
        <button class="btn-primary" type="submit" :disabled="saving">{{ saving ? 'Menyimpan…' : 'Simpan voucher' }}</button>
      </div>
    </form>
  </ModalDialog>
</template>
