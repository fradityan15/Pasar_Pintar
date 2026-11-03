<script setup>
import { onMounted, ref } from 'vue'
import { claimVoucher, listActiveVouchers, listMyVoucherClaims } from '@/services/voucherService'
import { formatRupiah, formatTanggalJam } from '@/lib/format'

const vouchers = ref([])
const claims = ref([])
const loading = ref(true)
const claiming = ref(false)
const code = ref('')
const error = ref('')
const notice = ref('')

async function load() {
  loading.value = true
  error.value = ''
  try {
    const [available, mine] = await Promise.all([listActiveVouchers(), listMyVoucherClaims()])
    vouchers.value = available ?? []
    claims.value = mine ?? []
  } catch (loadError) {
    error.value = loadError.message || 'Voucher belum dapat dimuat.'
  } finally {
    loading.value = false
  }
}

onMounted(load)

async function claim() {
  claiming.value = true
  error.value = ''
  notice.value = ''
  try {
    const result = await claimVoucher(code.value)
    notice.value = `Voucher ${result.code} berhasil diklaim dan kuotanya dicadangkan.`
    code.value = ''
    await load()
  } catch (claimError) {
    error.value = claimError.message || 'Voucher tidak dapat diklaim.'
  } finally {
    claiming.value = false
  }
}

function discountLabel(voucher) {
  return voucher.discount_type === 'persen'
    ? `${voucher.discount_value}%${voucher.maximum_discount != null ? ` · maksimum ${formatRupiah(voucher.maximum_discount)}` : ''}`
    : formatRupiah(voucher.discount_value)
}

function scopeLabel(voucher) {
  if (voucher.scope_type === 'stores') return 'Toko tertentu'
  if (voucher.scope_type === 'categories') return 'Kategori tertentu'
  return 'Semua toko'
}

const statusLabel = { claimed: 'Siap digunakan', used: 'Sudah digunakan', expired: 'Kedaluwarsa' }
</script>

<template>
  <div class="mx-auto max-w-5xl px-4 pb-16 pt-8 md:px-6 lg:px-8">
    <p class="text-sm font-medium text-indigo-700">Program subsidi</p>
    <h1 class="mt-1 text-3xl font-bold text-slate-900">Voucher GBBI</h1>
    <p class="mt-2 max-w-3xl text-sm leading-6 text-slate-600">Klaim kode voucher yang Anda miliki, lalu pilih klaim tersebut saat checkout. Syarat program ditentukan pengelola sesuai ketentuan resmi yang berlaku.</p>

    <form class="mt-6 flex flex-col gap-3 rounded-2xl border border-slate-200 bg-white p-5 shadow-sm sm:flex-row" @submit.prevent="claim">
      <label for="voucher-code" class="sr-only">Kode voucher</label>
      <input id="voucher-code" v-model="code" class="input min-w-0 flex-1 uppercase" maxlength="80" placeholder="Masukkan kode voucher" required />
      <button class="btn-primary" type="submit" :disabled="claiming">{{ claiming ? 'Mengklaim…' : 'Klaim voucher' }}</button>
    </form>
    <p v-if="error" class="mt-4 rounded-xl bg-bad-bg p-3 text-sm text-bad-fg" role="alert">{{ error }}</p>
    <p v-if="notice" class="mt-4 rounded-xl bg-ok-bg p-3 text-sm text-ok-fg" role="status">{{ notice }}</p>

    <section class="mt-8">
      <h2 class="text-lg font-semibold text-slate-900">Voucher yang sudah diklaim</h2>
      <div v-if="loading" class="mt-4 h-24 animate-pulse rounded-xl bg-slate-100"></div>
      <p v-else-if="!claims.length" class="mt-4 rounded-xl border border-dashed border-slate-300 p-6 text-sm text-slate-500">Belum ada voucher yang diklaim.</p>
      <div v-else class="mt-4 grid gap-4 md:grid-cols-2">
        <article v-for="voucher in claims" :key="voucher.claim_id" class="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
          <div class="flex items-start justify-between gap-3">
            <div><p class="font-mono text-lg font-bold text-gray-900">{{ voucher.code }}</p><p class="mt-1 text-sm font-semibold text-slate-700">{{ discountLabel(voucher) }}</p></div>
            <span class="badge" :class="voucher.claim_status === 'claimed' ? 'bg-ok-bg text-ok-fg' : 'bg-surface text-muted'">{{ statusLabel[voucher.claim_status] || voucher.claim_status }}</span>
          </div>
          <dl class="mt-4 space-y-1 text-xs text-slate-600">
            <div class="flex justify-between gap-2"><dt>Minimum belanja</dt><dd class="font-medium">{{ formatRupiah(voucher.minimum_purchase) }}</dd></div>
            <div class="flex justify-between gap-2"><dt>Cakupan</dt><dd class="font-medium">{{ scopeLabel(voucher) }}</dd></div>
            <div class="flex justify-between gap-2"><dt>Berlaku sampai</dt><dd class="font-medium">{{ formatTanggalJam(voucher.berlaku_sampai) }}</dd></div>
          </dl>
          <p v-if="voucher.order_id" class="mt-3 text-xs text-slate-500">Pesanan: {{ voucher.order_id }}</p>
        </article>
      </div>
    </section>

    <section class="mt-8">
      <h2 class="text-lg font-semibold text-slate-900">Voucher aktif</h2>
      <div v-if="!loading && !vouchers.length" class="mt-4 rounded-xl bg-slate-50 p-5 text-sm text-slate-500">Saat ini tidak ada voucher yang dapat diklaim.</div>
      <div class="mt-4 grid gap-4 md:grid-cols-2">
        <article v-for="voucher in vouchers" :key="voucher.id" class="rounded-xl border border-slate-200 bg-white p-5">
          <p class="font-mono text-lg font-bold text-gray-900">{{ voucher.code }}</p>
          <p class="mt-1 text-sm font-semibold text-slate-700">{{ discountLabel(voucher) }}</p>
          <p class="mt-2 text-xs text-slate-500">Minimum {{ formatRupiah(voucher.minimum_purchase) }} · {{ scopeLabel(voucher) }}</p>
          <p class="mt-1 text-xs text-slate-500">Berlaku sampai {{ formatTanggalJam(voucher.berlaku_sampai) }}</p>
          <p v-if="voucher.quota_total !== null" class="mt-1 text-xs text-slate-500">Kuota tersisa: {{ Math.max(0, voucher.quota_total - voucher.quota_used) }}</p>
        </article>
      </div>
      <p v-if="!loading && vouchers.length" class="mt-3 text-xs text-slate-500">Mengklaim mencadangkan satu kuota untuk akun Anda. Voucher yang diklaim berlaku untuk satu checkout dan kuotanya dikembalikan jika pesanan dibatalkan atau kedaluwarsa.</p>
    </section>
  </div>
</template>
