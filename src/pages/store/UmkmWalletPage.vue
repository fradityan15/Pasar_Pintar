<script setup>
import { computed, onMounted, ref } from 'vue'
import SellerDashboardSidebar from '@/components/SellerDashboardSidebar.vue'
import { formatRupiah, formatTanggalJam } from '@/lib/format'
import { getMyUmkm } from '@/services/umkmPartnerService'
import {
  getSellerWalletSummary,
  listSellerLedger,
  listSellerWithdrawals,
  requestSellerWithdrawal,
} from '@/services/walletService'

const umkm = ref(null)
const summary = ref({ held_balance: 0, available_balance: 0 })
const ledger = ref([])
const withdrawals = ref([])
const amount = ref('')
const loading = ref(true)
const submitting = ref(false)
const error = ref('')
const notice = ref('')

const available = computed(() => Number(summary.value.available_balance ?? 0))
const held = computed(() => Number(summary.value.held_balance ?? 0))
const ledgerLabels = {
  sale_credit: 'Hasil penjualan',
  commission_debit: 'Komisi platform',
  withdrawal_debit: 'Penarikan diajukan',
  withdrawal_reversal: 'Pengembalian saldo penarikan',
  refund_debit: 'Penyesuaian refund',
  escrow_refund: 'Refund escrow (informasi)',
}
const statusLabels = {
  pending: 'Menunggu persetujuan',
  approved: 'Disetujui · menunggu transfer',
  rejected: 'Ditolak',
  paid: 'Dana diterima · simulasi',
}

async function load() {
  loading.value = true
  error.value = ''
  try {
    umkm.value = await getMyUmkm()
    if (!umkm.value?.id) throw new Error('Data toko tidak ditemukan.')
    const [walletSummary, entries, requests] = await Promise.all([
      getSellerWalletSummary(umkm.value.id),
      listSellerLedger(umkm.value.id),
      listSellerWithdrawals(umkm.value.id),
    ])
    summary.value = walletSummary?.[0] ?? summary.value
    ledger.value = entries ?? []
    withdrawals.value = requests ?? []
  } catch (loadError) {
    error.value = loadError.message || 'Saldo toko tidak dapat dimuat.'
  } finally {
    loading.value = false
  }
}

async function submitWithdrawal() {
  const parsedAmount = Number(amount.value)
  error.value = ''
  notice.value = ''
  if (!Number.isSafeInteger(parsedAmount) || parsedAmount <= 0) {
    error.value = 'Masukkan jumlah penarikan dalam rupiah yang valid.'
    return
  }
  submitting.value = true
  try {
    await requestSellerWithdrawal(parsedAmount)
    amount.value = ''
    notice.value = 'Permintaan penarikan berhasil diajukan dan menunggu persetujuan admin.'
    await load()
  } catch (requestError) {
    error.value = requestError.message || 'Permintaan penarikan tidak dapat diajukan.'
  } finally {
    submitting.value = false
  }
}

onMounted(load)
</script>

<template>
  <div class="min-h-full bg-slate-50 lg:flex">
    <SellerDashboardSidebar :umkm="umkm" />
    <main class="min-w-0 flex-1 px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
      <div class="mx-auto max-w-7xl">
        <header>
          <p class="text-sm font-medium text-emerald-700">Keuangan toko</p>
          <h1 class="mt-1 text-2xl font-bold tracking-tight text-slate-900 sm:text-3xl">Saldo & Penarikan</h1>
          <p class="mt-1.5 text-sm text-slate-500">Setelah pembeli mengonfirmasi penerimaan, saldo bersih tersedia di sini. Ajukan pencairan; admin dapat menyimulasikan transfer dan status berhasil akan tampil di riwayat. Tidak ada uang sungguhan yang dikirim.</p>
        </header>

        <p v-if="error" class="mt-5 rounded-xl border border-red-100 bg-red-50 p-4 text-sm text-red-700" role="alert">{{ error }}</p>
        <p v-if="notice" class="mt-5 rounded-xl border border-emerald-100 bg-emerald-50 p-4 text-sm text-emerald-800" role="status">{{ notice }}</p>
        <div v-if="loading" class="mt-6 grid gap-4 sm:grid-cols-2">
          <div v-for="item in 2" :key="item" class="h-32 animate-pulse rounded-2xl bg-white shadow-sm" />
        </div>
        <template v-else>
          <section class="mt-6 grid gap-4 sm:grid-cols-2" aria-label="Ringkasan saldo">
            <article class="rounded-2xl bg-white p-5 shadow-sm ring-1 ring-slate-200">
              <p class="text-sm font-medium text-slate-500">Dana ditahan</p>
              <p class="mt-2 text-2xl font-bold text-slate-900">{{ formatRupiah(held) }}</p>
              <p class="mt-1 text-xs text-slate-500">Menunggu pesanan diterima atau auto-confirm</p>
            </article>
            <article class="rounded-2xl bg-white p-5 shadow-sm ring-1 ring-slate-200">
              <p class="text-sm font-medium text-slate-500">Saldo tersedia</p>
              <p class="mt-2 text-2xl font-bold text-slate-900">{{ formatRupiah(available) }}</p>
              <p class="mt-1 text-xs text-slate-500">Sudah dikurangi komisi dan pencairan yang diajukan</p>
            </article>
          </section>

          <section class="mt-6 rounded-2xl bg-white p-5 shadow-sm ring-1 ring-slate-200 sm:p-6">
            <h2 class="text-lg font-semibold text-slate-900">Ajukan pencairan ke admin</h2>
            <p class="mt-1 text-sm text-slate-500">Saldo akan dicadangkan saat pengajuan. Pastikan rekening pada Pengaturan Toko sudah benar. Admin menyetujui permintaan lalu menyimulasikan pencairan untuk memperbarui status di riwayat.</p>
            <form class="mt-4 flex flex-col gap-3 sm:flex-row sm:items-end" @submit.prevent="submitWithdrawal">
              <label class="min-w-0 flex-1 text-sm font-medium text-slate-700">
                Jumlah (rupiah)
                <input v-model="amount" class="input mt-1.5 w-full" type="number" min="1" step="1" :max="available" required />
              </label>
              <button class="btn min-h-11 bg-gray-900 px-5 text-white hover:bg-black" type="submit" :disabled="submitting || available <= 0">
                {{ submitting ? 'Mengajukan…' : 'Ajukan pencairan' }}
              </button>
            </form>
          </section>

          <section class="mt-6 overflow-hidden rounded-2xl bg-white shadow-sm ring-1 ring-slate-200">
            <div class="border-b border-slate-100 px-5 py-4">
              <h2 class="font-semibold text-slate-900">Riwayat permintaan penarikan</h2>
            </div>
            <div v-if="!withdrawals.length" class="p-5 text-sm text-slate-500">Belum ada permintaan penarikan.</div>
            <div v-else class="divide-y divide-slate-100">
              <article v-for="request in withdrawals" :key="request.id" class="flex flex-col gap-2 px-5 py-4 sm:flex-row sm:items-center sm:justify-between">
                <div>
                  <p class="font-semibold text-slate-900">{{ formatRupiah(request.amount) }} · {{ statusLabels[request.status] || request.status }}</p>
                  <p class="mt-1 text-xs text-slate-500">{{ request.bank_snapshot.bank_name }} · {{ request.bank_snapshot.account_number }} · {{ request.bank_snapshot.account_holder }}</p>
                  <p v-if="request.status === 'paid'" class="mt-1 text-xs font-medium text-emerald-700">Pencairan berhasil dicatat pada {{ request.paid_at ? formatTanggalJam(request.paid_at) : 'waktu tidak tersedia' }}. Ini simulasi, bukan transfer bank sungguhan.</p>
                  <p v-if="request.admin_note" class="mt-1 text-xs text-slate-600">Catatan admin: {{ request.admin_note }}</p>
                </div>
                <time class="text-xs text-slate-500" :datetime="request.requested_at">{{ formatTanggalJam(request.requested_at) }}</time>
              </article>
            </div>
          </section>

          <section class="mt-6 overflow-hidden rounded-2xl bg-white shadow-sm ring-1 ring-slate-200">
            <div class="border-b border-slate-100 px-5 py-4">
              <h2 class="font-semibold text-slate-900">Buku besar</h2>
              <p class="mt-1 text-sm text-slate-500">Entri hanya dapat ditambahkan oleh transaksi database dan tidak dapat diubah atau dihapus.</p>
            </div>
            <div v-if="!ledger.length" class="p-5 text-sm text-slate-500">Belum ada entri ledger.</div>
            <div v-else class="divide-y divide-slate-100">
              <article v-for="entry in ledger" :key="entry.id" class="flex flex-wrap items-center justify-between gap-3 px-5 py-3">
                <div>
                  <p class="text-sm font-semibold text-slate-800">{{ ledgerLabels[entry.entry_type] || entry.entry_type }}</p>
                  <p class="mt-0.5 text-xs text-slate-500">{{ entry.order_id ? `Pesanan ${entry.order_id}` : `Penarikan ${entry.withdrawal_id}` }}</p>
                </div>
                <div class="text-right">
                  <p class="text-sm font-bold" :class="Number(entry.amount) < 0 ? 'text-red-700' : 'text-emerald-700'">{{ formatRupiah(Math.abs(Number(entry.amount))) }}{{ Number(entry.amount) < 0 ? ' −' : ' +' }}</p>
                  <time class="text-xs text-slate-500" :datetime="entry.created_at">{{ formatTanggalJam(entry.created_at) }}</time>
                </div>
              </article>
            </div>
          </section>
        </template>
      </div>
    </main>
  </div>
</template>
