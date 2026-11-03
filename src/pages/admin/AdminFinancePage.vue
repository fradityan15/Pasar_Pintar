<script setup>
import { computed, onMounted, ref } from 'vue'
import AdminPageHeader from '@/components/AdminPageHeader.vue'
import { formatRupiah, formatTanggalJam } from '@/lib/format'
import { listAdminWithdrawals, processAdminWithdrawal } from '@/services/walletService'

const withdrawals = ref([])
const loading = ref(true)
const busyId = ref('')
const error = ref('')
const notice = ref('')
const notes = ref({})

const pendingCount = computed(() => withdrawals.value.filter((item) => item.status === 'pending').length)
const approvedCount = computed(() => withdrawals.value.filter((item) => item.status === 'approved').length)
const pendingAmount = computed(() => withdrawals.value
  .filter((item) => item.status === 'pending')
  .reduce((sum, item) => sum + Number(item.amount), 0))

const statusLabels = {
  pending: 'Menunggu persetujuan',
  approved: 'Disetujui · menunggu transfer',
  rejected: 'Ditolak',
  paid: 'Berhasil · simulasi',
}

async function load() {
  loading.value = true
  error.value = ''
  try {
    withdrawals.value = await listAdminWithdrawals() ?? []
  } catch (loadError) {
    error.value = loadError.message || 'Antrean penarikan tidak dapat dimuat.'
  } finally {
    loading.value = false
  }
}

async function processRequest(request, decision) {
  busyId.value = request.id
  error.value = ''
  notice.value = ''
  try {
    const note = decision === 'paid' && !notes.value[request.id]?.trim()
      ? 'Simulasi pencairan berhasil dicatat; tidak ada transfer bank sungguhan.'
      : notes.value[request.id] ?? ''
    await processAdminWithdrawal(request.id, decision, note)
    notice.value = decision === 'rejected'
      ? 'Permintaan ditolak dan saldo seller dikembalikan ke ledger.'
      : decision === 'paid'
        ? 'Simulasi pencairan berhasil. Seller dapat melihat statusnya di dashboard; tidak ada transfer bank sungguhan.'
        : 'Permintaan penarikan disetujui.'
    await load()
  } catch (processError) {
    error.value = processError.message || 'Status permintaan tidak dapat diperbarui.'
  } finally {
    busyId.value = ''
  }
}

onMounted(load)
</script>

<template>
  <AdminPageHeader title="Keuangan" desc="Alur presentasi: setujui pencairan lalu simulasikan transfer agar status berhasil tampil di dashboard seller. Tidak ada uang sungguhan yang dikirim." />

  <p v-if="error" class="mb-5 rounded-xl border border-red-100 bg-red-50 p-4 text-sm text-red-700" role="alert">{{ error }}</p>
  <p v-if="notice" class="mb-5 rounded-xl border border-emerald-100 bg-emerald-50 p-4 text-sm text-emerald-800" role="status">{{ notice }}</p>

  <section class="mb-6 grid gap-4 sm:grid-cols-3" aria-label="Ringkasan penarikan">
    <article class="card p-5">
      <p class="text-sm font-medium text-gray-600">Permintaan menunggu</p>
      <p class="mt-2 text-2xl font-bold tracking-tight text-gray-900">{{ pendingCount }}</p>
      <p class="mt-1 text-xs text-gray-500">Menunggu persetujuan admin</p>
    </article>
    <article class="card p-5">
      <p class="text-sm font-medium text-gray-600">Total antrean persetujuan</p>
      <p class="mt-2 text-2xl font-bold tracking-tight text-gray-900">{{ formatRupiah(pendingAmount) }}</p>
      <p class="mt-1 text-xs text-gray-500">Dana sudah dicadangkan di ledger</p>
    </article>
    <article class="card p-5">
      <p class="text-sm font-medium text-gray-600">Disetujui · menunggu transfer</p>
      <p class="mt-2 text-2xl font-bold tracking-tight text-gray-900">{{ approvedCount }}</p>
      <p class="mt-1 text-xs text-gray-500">Jalankan pencatatan simulasi untuk alur presentasi</p>
    </article>
  </section>

  <section class="card overflow-hidden">
    <div class="flex flex-wrap items-end justify-between gap-3 border-b border-line px-5 py-4">
      <div>
        <h2 class="font-semibold text-gray-900">Permintaan penarikan seller</h2>
        <p class="mt-1 text-sm text-muted">Setelah seller mengajukan pencairan, setujui lalu simulasikan transfer. Seller akan melihat status berhasil pada riwayatnya; tidak ada transfer bank sungguhan.</p>
      </div>
      <button class="btn-outline" type="button" :disabled="loading" @click="load">Muat ulang</button>
    </div>
    <div v-if="loading" class="p-6 text-sm text-muted">Memuat antrean…</div>
    <div v-else-if="!withdrawals.length" class="p-6 text-sm text-muted">Belum ada permintaan penarikan.</div>
    <div v-else class="overflow-x-auto">
      <table class="w-full min-w-[980px] text-left text-sm">
        <thead class="bg-gray-50 text-xs text-gray-600">
          <tr>
            <th class="px-5 py-3 font-medium">UMKM</th>
            <th class="px-5 py-3 text-right font-medium">Jumlah</th>
            <th class="px-5 py-3 font-medium">Rekening snapshot</th>
            <th class="px-5 py-3 font-medium">Diajukan</th>
            <th class="px-5 py-3 font-medium">Status</th>
            <th class="px-5 py-3 font-medium">Tindakan / catatan</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="request in withdrawals" :key="request.id" class="border-t border-line align-top">
            <td class="whitespace-nowrap px-5 py-4 font-semibold text-gray-900">{{ request.umkm_name }}</td>
            <td class="whitespace-nowrap px-5 py-4 text-right font-bold text-gray-900">{{ formatRupiah(request.amount) }}</td>
            <td class="px-5 py-4 text-gray-600">
              <p class="font-medium text-gray-800">{{ request.bank_snapshot.bank_name }}</p>
              <p class="font-mono text-xs">{{ request.bank_snapshot.account_number }}</p>
              <p class="text-xs">{{ request.bank_snapshot.account_holder }}</p>
            </td>
            <td class="whitespace-nowrap px-5 py-4 text-gray-600">{{ formatTanggalJam(request.requested_at) }}</td>
            <td class="whitespace-nowrap px-5 py-4">
              <span class="badge" :class="request.status === 'pending' ? 'bg-amber-100 text-amber-800' : request.status === 'paid' ? 'bg-gray-900 text-white' : 'bg-gray-100 text-gray-700'">
                {{ statusLabels[request.status] || request.status }}
              </span>
              <p v-if="request.admin_note" class="mt-2 max-w-48 whitespace-normal text-xs text-gray-500">{{ request.admin_note }}</p>
            </td>
            <td class="min-w-64 px-5 py-4">
              <textarea v-model="notes[request.id]" class="input min-h-16 w-full text-xs" maxlength="500" placeholder="Catatan admin (opsional)" />
              <div v-if="request.status === 'pending'" class="mt-2 flex gap-2">
                <button class="btn min-h-9 bg-gray-900 px-3 text-xs text-white hover:bg-black" type="button" :disabled="busyId === request.id" @click="processRequest(request, 'approved')">Setujui</button>
                <button class="btn-outline min-h-9 px-3 text-xs" type="button" :disabled="busyId === request.id" @click="processRequest(request, 'rejected')">Tolak</button>
              </div>
              <button v-else-if="request.status === 'approved'" class="btn min-h-9 mt-2 bg-gray-900 px-3 text-xs text-white hover:bg-black" type="button" :disabled="busyId === request.id" @click="processRequest(request, 'paid')">Simulasikan transfer</button>
              <p v-else-if="request.status === 'paid'" class="mt-2 text-xs text-gray-500">{{ request.paid_at ? formatTanggalJam(request.paid_at) : '' }}</p>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </section>
</template>
