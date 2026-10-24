<script setup>
import { computed, onMounted, ref } from 'vue'
import { Bar, Line } from 'vue-chartjs'
import { BarElement, CategoryScale, Chart as ChartJS, Filler, Legend, LinearScale, LineElement, PointElement, Tooltip } from 'chart.js'
import StatCard from '@/components/StatCard.vue'
import { useAuthStore } from '@/stores/auth'
import { getAdminDashboardCharts, getDashboardStats } from '@/services/adminService'
import { formatRupiah } from '@/lib/format'

ChartJS.register(CategoryScale, LinearScale, BarElement, LineElement, PointElement, Tooltip, Legend, Filler)

const auth = useAuthStore()
const stats = ref(null)
const analytics = ref(null)
const loading = ref(true)
const error = ref('')
const monthLabel = (value) => new Intl.DateTimeFormat('id-ID', { month: 'short', year: '2-digit', timeZone: 'UTC' })
  .format(new Date(`${value}-01T00:00:00Z`))
const umkmChartData = computed(() => ({
  labels: (analytics.value?.umkm ?? []).map((item) => monthLabel(item.bulan)),
  datasets: [
    {
      label: 'Status aktif saat ini',
      data: (analytics.value?.umkm ?? []).map((item) => Number(item.aktif)),
      backgroundColor: '#059669',
      borderRadius: 5,
      maxBarThickness: 28,
    },
    {
      label: 'Status pending saat ini',
      data: (analytics.value?.umkm ?? []).map((item) => Number(item.pending)),
      backgroundColor: '#a7f3d0',
      borderRadius: 5,
      maxBarThickness: 28,
    },
  ],
}))
const umkmChartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  plugins: { legend: { position: 'bottom', labels: { usePointStyle: true, boxWidth: 8, color: '#64748b' } } },
  scales: {
    x: { grid: { display: false }, ticks: { color: '#64748b' }, border: { display: false } },
    y: { beginAtZero: true, ticks: { precision: 0, color: '#64748b' }, grid: { color: '#e2e8f0' }, border: { display: false } },
  },
}
const transactionChartData = computed(() => ({
  labels: (analytics.value?.gmv ?? []).map((item) => new Intl.DateTimeFormat('id-ID', { day: 'numeric', month: 'short', timeZone: 'UTC' })
    .format(new Date(`${item.minggu_mulai}T00:00:00Z`))),
  datasets: [{
    label: 'Nilai transaksi',
    data: (analytics.value?.gmv ?? []).map((item) => Number(item.total)),
    borderColor: '#059669',
    backgroundColor: 'rgba(16, 185, 129, 0.12)',
    pointBackgroundColor: '#047857',
    pointBorderColor: '#ffffff',
    pointBorderWidth: 2,
    pointRadius: 4,
    pointHoverRadius: 6,
    borderWidth: 3,
    fill: true,
    tension: 0.35,
  }],
}))
const transactionChartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  interaction: { intersect: false, mode: 'index' },
  plugins: {
    legend: { display: false },
    tooltip: { callbacks: { label: (context) => `GMV: ${formatRupiah(context.parsed.y)}` } },
  },
  scales: {
    x: { grid: { display: false }, ticks: { color: '#64748b' }, border: { display: false } },
    y: {
      beginAtZero: true,
      ticks: { color: '#64748b', callback: (value) => formatRupiah(value) },
      grid: { color: '#e2e8f0' },
      border: { display: false },
    },
  },
}

async function load() {
  loading.value = true
  error.value = ''
  try {
    const [dashboardStats, dashboardCharts] = await Promise.all([getDashboardStats(), getAdminDashboardCharts()])
    stats.value = dashboardStats
    analytics.value = dashboardCharts
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}
onMounted(load)
</script>

<template>
  <div class="flex flex-col gap-5">
    <div>
      <h1 class="text-2xl font-bold">Halo, {{ auth.profile?.full_name || 'Admin' }}</h1>
      <p class="mt-1 text-sm text-muted">Ringkasan aktivitas PasarPintar hari ini.</p>
    </div>

    <p v-if="error" class="rounded-xl bg-bad-bg p-4 text-sm text-bad-fg" role="alert">
      Ringkasan belum bisa dimuat: {{ error }}
      <button class="ml-2 font-semibold underline" type="button" @click="load">Coba lagi</button>
    </p>
    <div v-else-if="loading" class="grid grid-cols-2 gap-4 lg:grid-cols-4">
      <div v-for="n in 4" :key="n" class="h-24 animate-pulse rounded-xl bg-white"></div>
    </div>
    <template v-else>
      <div class="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard label="Total produk" :value="stats.total_produk" />
        <StatCard label="Pesanan selesai" :value="stats.pesanan_selesai" />
        <StatCard label="Pesanan dibatalkan" :value="stats.pesanan_dibatalkan" />
        <StatCard label="UMKM aktif" :value="stats.umkm_aktif" />
      </div>

      <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <section class="rounded-xl bg-white p-5 shadow-sm ring-1 ring-line sm:p-6">
          <div class="flex flex-wrap items-start justify-between gap-2">
            <div>
              <h2 class="text-base font-semibold text-ink">Pertumbuhan Mitra UMKM</h2>
              <p class="mt-1 text-sm text-muted">Jumlah UMKM yang terdaftar per bulan, dikelompokkan menurut status saat ini.</p>
            </div>
          </div>
          <p v-if="!analytics?.umkm?.some((item) => Number(item.aktif) + Number(item.pending) > 0)" class="mt-5 rounded-lg bg-surface p-4 text-sm text-muted">Belum ada data UMKM pada periode ini.</p>
          <div v-else class="mt-5 h-64">
            <Bar :data="umkmChartData" :options="umkmChartOptions" />
          </div>
        </section>

        <section class="rounded-xl bg-white p-5 shadow-sm ring-1 ring-line sm:p-6">
          <div class="flex flex-wrap items-start justify-between gap-2">
            <div>
              <h2 class="text-base font-semibold text-ink">Tren Transaksi Platform</h2>
              <p class="mt-1 text-sm text-muted">Nilai pesanan yang dibayar dalam lima minggu terakhir.</p>
            </div>
          </div>
          <p v-if="!analytics?.gmv?.some((item) => Number(item.total) > 0)" class="mt-5 rounded-lg bg-surface p-4 text-sm text-muted">Belum ada transaksi dibayar pada periode ini.</p>
          <div v-else class="mt-5 h-64">
            <Line :data="transactionChartData" :options="transactionChartOptions" />
          </div>
        </section>
      </div>

      <div class="grid gap-4 lg:grid-cols-[1fr_320px]">
        <div class="card p-6">
          <p class="text-base font-semibold">Omzet 7 hari terakhir</p>
          <p class="mt-3 text-4xl font-bold">{{ formatRupiah(stats.omzet_7_hari) }}</p>
          <p class="mt-2 text-sm text-muted">Dari pesanan yang sudah dibayar dan tidak dibatalkan.</p>
        </div>
        <div class="card flex flex-col gap-2.5 bg-[#FAFAFB] p-5">
          <p class="text-base font-semibold">Perlu tindakan</p>
          <div class="flex items-center justify-between rounded-xl bg-white px-4 py-3.5 text-sm">
            Menunggu pembayaran <b>{{ stats.menunggu_pembayaran }}</b>
          </div>
          <div class="flex items-center justify-between rounded-xl bg-white px-4 py-3.5 text-sm">
            Stok menipis <b>{{ stats.stok_menipis }}</b>
          </div>
          <div class="flex items-center justify-between rounded-xl bg-white px-4 py-3.5 text-sm">
            UMKM belum diverifikasi <b>{{ stats.umkm_belum_verifikasi }}</b>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
