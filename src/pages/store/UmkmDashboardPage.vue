<script setup>
import { computed, onMounted, ref } from 'vue'
import { RouterLink } from 'vue-router'
import { ArcElement, CategoryScale, Chart as ChartJS, Filler, Legend, LinearScale, LineElement, PointElement, Tooltip } from 'chart.js'
import { Doughnut, Line } from 'vue-chartjs'
import SellerDashboardSidebar from '@/components/SellerDashboardSidebar.vue'
import { formatRupiah, formatTanggalJam } from '@/lib/format'
import { getMyUmkm, getMyUmkmDashboardMetrics, listMyUmkmProducts } from '@/services/umkmPartnerService'
import { listSellerOrders } from '@/services/sellerOrderService'

ChartJS.register(ArcElement, CategoryScale, LinearScale, PointElement, LineElement, Tooltip, Legend, Filler)

const umkm = ref(null)
const products = ref([])
const orders = ref([])
const metrics = ref(null)
const loading = ref(true)
const error = ref('')
const canManage = computed(() => umkm.value?.status === 'active' && umkm.value.is_active)
const recentOrders = computed(() => orders.value
  .filter((order) => order.seller_shipping_status === 'menunggu_diproses')
  .slice(0, 5))
const totalIncome = computed(() => Number(metrics.value?.total_pendapatan ?? 0))
const pendingOrders = computed(() => Number(metrics.value?.pesanan_baru ?? 0))
const activeProducts = computed(() => products.value.filter((product) => product.is_active).length)
const categoryChartData = computed(() => {
  const counts = new Map()
  for (const product of products.value) {
    const category = product.categories?.name || 'Tanpa kategori'
    counts.set(category, (counts.get(category) ?? 0) + 1)
  }
  const entries = [...counts.entries()]
  return {
    labels: entries.map(([category]) => category),
    datasets: [{
      data: entries.map(([, count]) => count),
      backgroundColor: ['#059669', '#0ea5e9', '#f59e0b', '#8b5cf6', '#f43f5e', '#14b8a6', '#64748b'],
      borderWidth: 0,
      hoverOffset: 5,
    }],
  }
})
const hasSalesData = computed(() => (metrics.value?.pendapatan_harian ?? [])
  .some((item) => Number(item.omzet) > 0)
  || (metrics.value?.penjualan_harian ?? []).some((item) => Number(item.jumlah) > 0))
const salesChartData = computed(() => {
  const revenue = metrics.value?.pendapatan_harian ?? []
  const sales = metrics.value?.penjualan_harian ?? []
  return {
    labels: revenue.map((item) => new Intl.DateTimeFormat('id-ID', {
      weekday: 'short',
      timeZone: 'UTC',
    }).format(new Date(`${item.tanggal}T00:00:00Z`))),
    datasets: [
      {
        label: 'Pendapatan',
        data: revenue.map((item) => Number(item.omzet)),
        yAxisID: 'revenue',
        borderColor: '#047857',
        backgroundColor: 'rgba(16, 185, 129, 0.12)',
        pointBackgroundColor: '#047857',
        pointBorderColor: '#ffffff',
        pointBorderWidth: 2,
        pointRadius: 4,
        borderWidth: 3,
        fill: true,
        tension: 0.35,
      },
      {
        label: 'Unit terjual',
        data: sales.map((item) => Number(item.jumlah)),
        yAxisID: 'units',
        borderColor: '#0ea5e9',
        pointBackgroundColor: '#0ea5e9',
        pointRadius: 4,
        borderWidth: 2,
        tension: 0.35,
      },
    ],
  }
})
const salesChartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  interaction: { intersect: false, mode: 'index' },
  plugins: {
    legend: { position: 'bottom', labels: { usePointStyle: true, boxWidth: 8, color: '#475569' } },
    tooltip: {
      callbacks: {
        label: (context) => context.dataset.yAxisID === 'revenue'
          ? `${context.dataset.label}: ${formatRupiah(context.parsed.y)}`
          : `${context.dataset.label}: ${context.parsed.y}`,
      },
    },
  },
  scales: {
    x: { grid: { display: false }, ticks: { color: '#64748b' }, border: { display: false } },
    revenue: {
      type: 'linear',
      position: 'left',
      beginAtZero: true,
      ticks: { color: '#64748b', callback: (value) => formatRupiah(value) },
      grid: { color: '#e2e8f0', borderDash: [4, 4] },
      border: { display: false },
    },
    units: {
      type: 'linear',
      position: 'right',
      beginAtZero: true,
      ticks: { color: '#64748b', precision: 0 },
      grid: { drawOnChartArea: false },
      border: { display: false },
    },
  },
}
const categoryChartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  cutout: '68%',
  plugins: { legend: { position: 'bottom', labels: { usePointStyle: true, boxWidth: 8, color: '#475569' } } },
}

async function load() {
  loading.value = true
  error.value = ''
  try {
    umkm.value = await getMyUmkm()
    if (canManage.value) {
      const [dashboardMetrics, myProducts, sellerOrders] = await Promise.all([
        getMyUmkmDashboardMetrics(umkm.value.id),
        listMyUmkmProducts(umkm.value.id),
        listSellerOrders(umkm.value.id),
      ])
      metrics.value = dashboardMetrics
      products.value = myProducts
      orders.value = sellerOrders
    } else {
      metrics.value = null
      products.value = []
      orders.value = []
    }
  } catch (loadError) {
    error.value = loadError.message
  } finally {
    loading.value = false
  }
}

onMounted(load)
</script>

<template>
  <div class="min-h-full bg-slate-50 lg:flex">
    <SellerDashboardSidebar :umkm="umkm" />
    <main id="ringkasan" class="min-w-0 flex-1 scroll-mt-6 px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
      <div class="mx-auto max-w-7xl">
        <header class="flex flex-wrap items-end justify-between gap-4">
          <div>
            <p class="text-sm font-medium text-emerald-700">Dasbor penjual</p>
            <h1 class="mt-1 text-2xl font-bold tracking-tight text-slate-900 sm:text-3xl">Ringkasan Toko</h1>
            <p class="mt-1.5 text-sm text-slate-500">Pantau performa dan aktivitas {{ umkm?.name || 'toko Anda' }}.</p>
          </div>
          <span v-if="canManage" class="inline-flex items-center gap-2 rounded-full bg-emerald-50 px-3 py-1.5 text-xs font-semibold text-emerald-700">
            <span class="h-2 w-2 rounded-full bg-emerald-500"></span>Toko aktif
          </span>
        </header>

        <p v-if="error" class="mt-5 rounded-xl border border-red-100 bg-red-50 p-4 text-sm text-red-700" role="alert">
          {{ error }} <button class="font-semibold underline" type="button" @click="load">Coba lagi</button>
        </p>
        <div v-if="loading" class="mt-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <div v-for="n in 4" :key="n" class="h-32 animate-pulse rounded-2xl bg-white shadow-sm ring-1 ring-slate-200"></div>
        </div>
        <div v-else-if="!umkm" class="mt-6 rounded-xl border border-slate-200 bg-white p-6">
          <p class="font-semibold text-slate-900">Data UMKM tidak ditemukan.</p>
          <RouterLink :to="{ name: 'akun' }" class="mt-2 inline-block text-sm font-semibold text-emerald-700 underline">Periksa pendaftaran di halaman akun</RouterLink>
        </div>
        <div v-else-if="!canManage" class="mt-6 rounded-xl border border-amber-200 bg-amber-50 p-5 text-sm text-amber-900" role="status">
          Pendaftaran UMKM belum aktif. Analitik tersedia setelah Admin PasarPintar menyetujui dan mengaktifkan toko.
        </div>
        <template v-else>
          <section class="mt-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-4" aria-label="Metrik toko">
            <article class="rounded-2xl bg-white p-5 shadow-sm ring-1 ring-slate-200">
              <div class="flex items-start justify-between gap-3">
                <div><p class="text-sm font-medium text-slate-500">Total Pendapatan</p><p class="mt-3 text-2xl font-bold tracking-tight text-slate-900">{{ formatRupiah(totalIncome) }}</p><p class="mt-1 text-xs text-slate-500">Akumulasi penjualan dibayar</p></div>
                <span class="rounded-xl bg-emerald-50 p-3 text-lg font-bold text-emerald-700">Rp</span>
              </div>
            </article>
            <article class="rounded-2xl bg-white p-5 shadow-sm ring-1 ring-slate-200">
              <div class="flex items-start justify-between gap-3">
                <div><p class="text-sm font-medium text-slate-500">Pesanan Masuk</p><p class="mt-3 text-3xl font-bold tracking-tight text-slate-900">{{ pendingOrders }}</p><p class="mt-1 text-xs text-slate-500">Menunggu diproses</p></div>
                <span class="rounded-xl bg-amber-50 p-3 text-amber-700"><svg viewBox="0 0 24 24" class="h-6 w-6" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="M5 8h14l1 12H4L5 8Zm4 0a3 3 0 0 1 6 0" /></svg></span>
              </div>
            </article>
            <article class="rounded-2xl bg-white p-5 shadow-sm ring-1 ring-slate-200">
              <div class="flex items-start justify-between gap-3">
                <div><p class="text-sm font-medium text-slate-500">Produk Aktif</p><p class="mt-3 text-3xl font-bold tracking-tight text-slate-900">{{ activeProducts }}</p><p class="mt-1 text-xs text-slate-500">Dari {{ products.length }} produk</p></div>
                <span class="rounded-xl bg-blue-50 p-3 text-blue-700"><svg viewBox="0 0 24 24" class="h-6 w-6" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="m3 7 9-4 9 4-9 4-9-4Zm0 0v10l9 4 9-4V7M12 11v10" /></svg></span>
              </div>
            </article>
            <article class="rounded-2xl bg-white p-5 shadow-sm ring-1 ring-slate-200">
              <div class="flex items-start justify-between gap-3">
                <div><p class="text-sm font-medium text-slate-500">Kunjungan Toko</p><p class="mt-3 text-2xl font-bold tracking-tight text-slate-900">Belum tersedia</p><p class="mt-1 text-xs text-slate-500">Pelacakan kunjungan belum diaktifkan</p></div>
                <span class="rounded-xl bg-violet-50 p-3 text-violet-700"><svg viewBox="0 0 24 24" class="h-6 w-6" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="M2 12s3.6-6 10-6 10 6 10 6-3.6 6-10 6-10-6-10-6Z" /><circle cx="12" cy="12" r="2.5" /></svg></span>
              </div>
            </article>
          </section>

          <section class="mt-6 grid gap-6 xl:grid-cols-[minmax(0,1.8fr)_minmax(18rem,1fr)]">
            <article class="min-w-0 rounded-2xl bg-white p-5 shadow-sm ring-1 ring-slate-200 sm:p-6">
              <div>
                <h2 class="text-lg font-semibold text-slate-900">Pendapatan & Penjualan</h2>
                <p class="mt-1 text-sm text-slate-500">Tren pendapatan dan unit terjual selama 7 hari terakhir.</p>
              </div>
              <p v-if="!hasSalesData" class="mt-5 rounded-lg bg-slate-50 p-4 text-sm text-slate-500">Belum ada penjualan dalam tujuh hari terakhir.</p>
              <div v-else class="mt-5 h-[300px]"><Line :data="salesChartData" :options="salesChartOptions" /></div>
            </article>
            <article class="rounded-2xl bg-white p-5 shadow-sm ring-1 ring-slate-200 sm:p-6">
              <div>
                <h2 class="text-lg font-semibold text-slate-900">Komposisi Katalog</h2>
                <p class="mt-1 text-sm text-slate-500">Jumlah produk yang dikelompokkan menurut kategori.</p>
              </div>
              <p v-if="!products.length" class="mt-5 rounded-lg bg-slate-50 p-4 text-sm text-slate-500">Belum ada produk untuk ditampilkan.</p>
              <div v-else class="mx-auto mt-4 h-[260px] max-w-sm"><Doughnut :data="categoryChartData" :options="categoryChartOptions" /></div>
            </article>
          </section>

          <section class="mt-6 overflow-hidden rounded-2xl bg-white shadow-sm ring-1 ring-slate-200" aria-labelledby="recent-orders-title">
            <div class="flex flex-wrap items-center justify-between gap-3 border-b border-slate-100 px-5 py-4 sm:px-6">
              <div><h2 id="recent-orders-title" class="text-lg font-semibold text-slate-900">Pesanan yang Perlu Diproses</h2><p class="mt-1 text-sm text-slate-500">Maksimal lima pesanan terbaru yang menunggu tindakan.</p></div>
              <RouterLink :to="{ name: 'umkm-orders' }" class="text-sm font-semibold text-emerald-700 hover:text-emerald-800">Semua pesanan →</RouterLink>
            </div>
            <div v-if="recentOrders.length" class="divide-y divide-slate-100">
              <div v-for="order in recentOrders" :key="order.order_id" class="flex flex-col gap-2 px-5 py-4 sm:flex-row sm:items-center sm:justify-between sm:px-6">
                <div class="min-w-0">
                  <p class="font-semibold text-slate-900">{{ order.order_no }} <span class="font-normal text-slate-500">· {{ order.customer_name }}</span></p>
                  <p class="mt-1 truncate text-sm text-slate-500">{{ (order.products ?? []).map((item) => `${item.product_name} × ${item.quantity}`).join(', ') }}</p>
                  <p class="mt-1 text-xs text-slate-400">{{ formatTanggalJam(order.created_at) }}</p>
                </div>
                <div class="flex items-center justify-between gap-4 sm:justify-end">
                  <span class="font-semibold text-slate-900">{{ formatRupiah(order.total) }}</span>
                  <span class="rounded-full bg-amber-50 px-3 py-1 text-xs font-semibold text-amber-700">Perlu diproses</span>
                </div>
              </div>
            </div>
            <p v-else class="px-5 py-10 text-center text-sm text-slate-500">Tidak ada pesanan yang menunggu diproses.</p>
          </section>
        </template>
      </div>
    </main>
  </div>
</template>
