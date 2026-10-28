<script setup>
import AdminPageHeader from '@/components/AdminPageHeader.vue'
import { formatRupiah, formatTanggal } from '@/lib/format'

const payouts = [
  { id: 'PO-2026-1048', umkm: 'Batik Sekar Arum', amount: 2750000, bank: 'BCA ···· 4821', date: '2026-10-27', status: 'Berhasil' },
  { id: 'PO-2026-1047', umkm: 'Kerajinan Bambu Lestari', amount: 1850000, bank: 'BRI ···· 9014', date: '2026-10-27', status: 'Diproses' },
  { id: 'PO-2026-1046', umkm: 'Kopi Lereng Merapi', amount: 4325000, bank: 'Bank Mandiri ···· 3176', date: '2026-10-26', status: 'Berhasil' },
  { id: 'PO-2026-1045', umkm: 'Tenun Pesisir', amount: 1275000, bank: 'BNI ···· 6620', date: '2026-10-25', status: 'Diproses' },
  { id: 'PO-2026-1044', umkm: 'Dapur Rempah Nusantara', amount: 3680000, bank: 'BCA ···· 1583', date: '2026-10-24', status: 'Berhasil' },
  { id: 'PO-2026-1043', umkm: 'Gerabah Kasongan', amount: 2150000, bank: 'BRI ···· 7442', date: '2026-10-23', status: 'Berhasil' },
]

const summaries = [
  { label: 'Saldo platform', value: 28475000, detail: 'Saldo tersedia saat ini' },
  { label: 'Pencairan diproses', value: 3125000, detail: '2 permintaan menunggu' },
  { label: 'Total pencairan bulan ini', value: 18640000, detail: '12 transaksi pencairan' },
]
</script>

<template>
  <AdminPageHeader title="Keuangan" desc="Pantau saldo platform dan pencairan dana mitra UMKM." />

  <section class="mb-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-3" aria-label="Ringkasan keuangan">
    <article v-for="summary in summaries" :key="summary.label" class="card p-5">
      <p class="text-sm font-medium text-gray-600">{{ summary.label }}</p>
      <p class="mt-2 text-2xl font-bold tracking-tight text-gray-900">{{ formatRupiah(summary.value) }}</p>
      <p class="mt-1 text-xs text-gray-500">{{ summary.detail }}</p>
    </article>
  </section>

  <section class="card overflow-hidden">
    <div class="flex flex-wrap items-end justify-between gap-3 border-b border-line px-5 py-4">
      <div>
        <h2 class="font-semibold text-gray-900">Riwayat pencairan dana</h2>
        <p class="mt-1 text-sm text-muted">Daftar pencairan dana mitra UMKM.</p>
      </div>
    </div>
    <div class="overflow-x-auto">
      <table class="w-full min-w-[760px] text-left text-sm">
        <thead class="bg-gray-50 text-xs text-gray-600">
          <tr>
            <th class="px-5 py-3 font-medium">ID pencairan</th>
            <th class="px-5 py-3 font-medium">Nama UMKM</th>
            <th class="px-5 py-3 text-right font-medium">Jumlah</th>
            <th class="px-5 py-3 font-medium">Bank</th>
            <th class="px-5 py-3 font-medium">Tanggal</th>
            <th class="px-5 py-3 font-medium">Status</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="payout in payouts" :key="payout.id" class="border-t border-line">
            <td class="whitespace-nowrap px-5 py-4 font-medium text-gray-700">{{ payout.id }}</td>
            <td class="whitespace-nowrap px-5 py-4 font-semibold text-gray-900">{{ payout.umkm }}</td>
            <td class="whitespace-nowrap px-5 py-4 text-right font-bold text-gray-900">{{ formatRupiah(payout.amount) }}</td>
            <td class="whitespace-nowrap px-5 py-4 text-gray-600">{{ payout.bank }}</td>
            <td class="whitespace-nowrap px-5 py-4 text-gray-600">{{ formatTanggal(payout.date) }}</td>
            <td class="px-5 py-4">
              <span class="badge" :class="payout.status === 'Berhasil' ? 'bg-gray-900 text-white' : 'bg-gray-100 text-gray-700'">{{ payout.status }}</span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </section>
</template>
