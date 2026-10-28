<script setup>
import { computed, onMounted, ref } from 'vue'
import { Line } from 'vue-chartjs'
import { CategoryScale, Chart as ChartJS, Filler, LinearScale, LineElement, PointElement, Tooltip } from 'chart.js'
import { useAuthStore } from '@/stores/auth'
import { getAdminGlobalAnalytics } from '@/services/adminService'
import { formatRupiah } from '@/lib/format'

ChartJS.register(CategoryScale, LinearScale, LineElement, PointElement, Tooltip, Filler)

const auth = useAuthStore()
const analytics = ref(null)
const loading = ref(true)
const error = ref('')
const numberFormat = new Intl.NumberFormat('id-ID')

const metricCards = computed(() => [
  {
    label: 'Total Transaksi Sukses',
    value: numberFormat.format(Number(analytics.value?.total_transaksi_sukses ?? 0)),
    detail: 'Pesanan dibayar dan tidak dibatalkan',
    iconClass: 'bg-emerald-50 text-emerald-700',
    iconPath: 'M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01',
  },
  {
    label: 'Total Pendapatan Platform',
    value: formatRupiah(analytics.value?.total_pendapatan_platform),
    detail: 'GMV produk dari transaksi sukses',
    iconClass: 'bg-gray-100 text-gray-900',
    iconLabel: 'Rp',
  },
  {
    label: 'Jumlah UMKM Aktif',
    value: numberFormat.format(Number(analytics.value?.jumlah_umkm_aktif ?? 0)),
    detail: 'Toko disetujui dan aktif',
    iconClass: 'bg-violet-50 text-violet-700',
    iconPath: 'M3 21h18M5 21V7l8-4v18M19 21V11l-6-4M9 9v.01M9 12v.01M9 15v.01M9 18v.01',
  },
  {
    label: 'Total Pengguna',
    value: numberFormat.format(Number(analytics.value?.total_pengguna ?? 0)),
    detail: 'Akun dengan profil terdaftar',
    iconClass: 'bg-amber-50 text-amber-700',
    iconPath: 'M16 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2m6-10a4 4 0 1 0 0-8 4 4 0 0 0 0 8m10 10v-2a4 4 0 0 0-3-3.87m-1-11.13a4 4 0 0 1 0 7.75',
  },
])

const trend = computed(() => analytics.value?.tren_transaksi_30_hari ?? [])
const leaderboard = computed(() => analytics.value?.top_umkm ?? [])
const trendChartData = computed(() => ({
  labels: trend.value.map((row) => new Intl.DateTimeFormat('id-ID', {
    day: 'numeric',
    month: 'short',
    timeZone: 'UTC',
  }).format(new Date(`${row.tanggal}T00:00:00Z`))),
  datasets: [{
    label: 'Transaksi sukses',
    data: trend.value.map((row) => Number(row.jumlah)),
    borderColor: '#059669',
    backgroundColor: 'rgba(5, 150, 105, 0.12)',
    pointBackgroundColor: '#ffffff',
    pointBorderColor: '#059669',
    pointBorderWidth: 2,
    pointRadius: 3,
    pointHoverRadius: 5,
    borderWidth: 3,
    fill: true,
    tension: 0.35,
  }],
}))
const trendChartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  interaction: { intersect: false, mode: 'index' },
  plugins: {
    legend: { display: false },
    tooltip: {
      callbacks: {
        label: (context) => `Transaksi: ${numberFormat.format(context.parsed.y)}`,
      },
    },
  },
  scales: {
    x: {
      grid: { display: false },
      ticks: { autoSkip: true, maxTicksLimit: 10, color: '#64748b' },
      border: { display: false },
    },
    y: {
      beginAtZero: true,
      ticks: { precision: 0, color: '#64748b' },
      grid: { color: '#e2e8f0' },
      border: { display: false },
    },
  },
}

async function load() {
  loading.value = true
  error.value = ''
  try {
    analytics.value = await getAdminGlobalAnalytics()
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

onMounted(load)
</script>

<template>
  <div class="space-y-6">
    <header class="flex flex-wrap items-end justify-between gap-3">
      <div>
        <p class="text-sm font-medium text-emerald-700">Analitik platform</p>
        <h1 class="mt-1 text-2xl font-bold tracking-tight text-slate-900">
          Halo, {{ auth.profile?.full_name || 'Admin' }}
        </h1>
        <p class="mt-1 text-sm text-slate-500">Ringkasan performa global PasarPintar.</p>
      </div>
      <button class="btn-outline" type="button" :disabled="loading" @click="load">
        {{ loading ? 'Memuat…' : 'Muat ulang' }}
      </button>
    </header>

    <p v-if="error" class="rounded-xl border border-red-100 bg-red-50 p-4 text-sm text-red-700" role="alert">
      Data analitik belum bisa dimuat: {{ error }}
      <button class="ml-2 font-semibold underline" type="button" @click="load">Coba lagi</button>
    </p>

    <div v-if="loading && !analytics" class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
      <div v-for="n in 4" :key="n" class="h-36 animate-pulse rounded-2xl bg-white shadow-sm ring-1 ring-slate-200"></div>
    </div>

    <template v-else-if="analytics">
      <section class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4" aria-label="Metrik platform">
        <article v-for="card in metricCards" :key="card.label" class="rounded-2xl bg-white p-5 shadow-sm ring-1 ring-slate-200">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <p class="text-sm font-medium text-slate-500">{{ card.label }}</p>
              <p class="mt-3 break-words text-2xl font-bold tracking-tight text-slate-900">{{ card.value }}</p>
            </div>
            <span class="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl" :class="card.iconClass" aria-hidden="true">
              <span v-if="card.iconLabel" class="text-sm font-bold">{{ card.iconLabel }}</span>
              <svg v-else class="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                <path :d="card.iconPath" />
              </svg>
            </span>
          </div>
          <p class="mt-3 text-xs text-slate-400">{{ card.detail }}</p>
        </article>
      </section>

      <section class="rounded-2xl bg-white p-5 shadow-sm ring-1 ring-slate-200 sm:p-6">
        <div class="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h2 class="text-lg font-bold text-slate-900">Tren Transaksi 30 Hari Terakhir</h2>
            <p class="mt-1 text-sm text-slate-500">Jumlah transaksi sukses per hari berdasarkan waktu pembayaran.</p>
          </div>
          <span class="rounded-full bg-emerald-50 px-3 py-1 text-xs font-semibold text-emerald-700">30 hari</span>
        </div>
        <p v-if="!trend.some((row) => Number(row.jumlah) > 0)" class="mt-5 rounded-xl bg-slate-50 p-5 text-sm text-slate-500">
          Belum ada transaksi sukses dalam periode ini.
        </p>
        <div v-else class="mt-5 h-64">
          <Line :data="trendChartData" :options="trendChartOptions" />
        </div>
      </section>

      <section class="overflow-hidden rounded-2xl bg-white shadow-sm ring-1 ring-slate-200">
        <div class="border-b border-slate-100 px-5 py-5 sm:px-6">
          <h2 class="text-lg font-bold text-slate-900">5 UMKM dengan Penjualan Tertinggi</h2>
          <p class="mt-1 text-sm text-slate-500">Diurutkan berdasarkan nilai produk dari transaksi yang sukses.</p>
        </div>
        <div v-if="!leaderboard.length" class="px-6 py-12 text-center text-sm text-slate-500">
          Belum ada penjualan sukses dari UMKM aktif.
        </div>
        <div v-else class="overflow-x-auto">
          <table class="w-full min-w-[640px] text-left text-sm">
            <thead class="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th class="px-6 py-3 text-left font-semibold">Peringkat</th>
                <th class="px-6 py-3 text-left font-semibold">UMKM</th>
                <th class="px-6 py-3 text-center font-semibold">Transaksi</th>
                <th class="px-6 py-3 text-right font-semibold">Total Penjualan</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="(umkm, index) in leaderboard" :key="umkm.umkm_id" class="border-t border-slate-100">
                <td class="px-6 py-4 text-left">
                  <span class="font-semibold text-gray-900">{{ index + 1 }}</span>
                </td>
                <td class="px-6 py-4 text-left font-semibold text-slate-800">{{ umkm.nama }}</td>
                <td class="px-6 py-4 text-center text-slate-600">{{ numberFormat.format(Number(umkm.jumlah_transaksi)) }}</td>
                <td class="px-6 py-4 text-right font-bold text-gray-900">{{ formatRupiah(umkm.total_penjualan) }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </template>
  </div>
</template>
