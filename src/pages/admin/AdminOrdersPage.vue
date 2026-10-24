<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { RouterLink } from 'vue-router'
import { Chart as ChartJS, CategoryScale, Filler, LinearScale, LineElement, PointElement, Tooltip } from 'chart.js'
import { Line } from 'vue-chartjs'
import AdminPageHeader from '@/components/AdminPageHeader.vue'
import PaginationBar from '@/components/PaginationBar.vue'
import StatusBadge from '@/components/StatusBadge.vue'
import { useQueryState } from '@/composables/useQueryState'
import { expireUnpaidOrders, listOrders } from '@/services/adminOrderService'
import { listUmkmAdmin } from '@/services/adminCatalogService'
import { getAdminDashboardCharts } from '@/services/adminService'
import { formatRupiah, formatTanggalJam } from '@/lib/format'
import { ORDER_STATUS, PAYMENT_METHOD } from '@/lib/status'
import { todayJakarta } from '@/lib/csv'

ChartJS.register(CategoryScale, LinearScale, LineElement, PointElement, Tooltip, Filler)

const { route, str, num, set } = useQueryState()
const items = ref([])
const umkmOptions = ref([])
const total = ref(0)
const loading = ref(true)
const error = ref('')
const notice = ref('')
const search = ref(str('q'))
const selectedUmkm = ref(str('umkm'))
const selectedMonth = ref(str('month') || todayJakarta().slice(0, 7))
const tabs = [['', 'Semua'], ...Object.entries(ORDER_STATUS).map(([k, v]) => [k, v.label])]
const months = computed(() => {
  const current = todayJakarta().slice(0, 7)
  const [year, month] = current.split('-').map(Number)
  return [
    { value: 'all', label: 'Semua waktu' },
    ...[0, 1, 2, 3, 4, 5].map((offset) => {
      const date = new Date(Date.UTC(year, month - 1 - offset, 1))
      const value = `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, '0')}`
      return {
        value,
        label: new Intl.DateTimeFormat('id-ID', { month: 'long', year: 'numeric', timeZone: 'UTC' }).format(date),
      }
    }),
  ]
})
const dailyOrderRows = ref([])
const dailyOrderChartData = computed(() => ({
  labels: dailyOrderRows.value.map((item) => new Intl.DateTimeFormat('id-ID', { weekday: 'short', timeZone: 'UTC' })
    .format(new Date(`${item.tanggal}T00:00:00Z`))),
  datasets: [{
    label: 'Jumlah pesanan',
    data: dailyOrderRows.value.map((item) => Number(item.jumlah)),
    borderColor: '#059669',
    backgroundColor: 'rgba(16, 185, 129, 0.12)',
    pointBackgroundColor: '#047857',
    pointBorderColor: '#ffffff',
    pointBorderWidth: 2,
    pointRadius: 3,
    pointHoverRadius: 5,
    borderWidth: 2.5,
    fill: true,
    tension: 0.4,
  }],
}))
const dailyOrderChartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  interaction: { intersect: false, mode: 'index' },
  plugins: {
    legend: { display: false },
    tooltip: { callbacks: { label: (context) => `Pesanan: ${context.parsed.y}` } },
  },
  scales: {
    x: { grid: { display: false }, ticks: { color: '#64748b' }, border: { display: false } },
    y: {
      beginAtZero: true,
      ticks: { precision: 0, color: '#64748b' },
      grid: { color: '#e2e8f0' },
      border: { display: false },
    },
  },
}
let req = 0

async function load() {
  const id = ++req
  loading.value = true
  error.value = ''
  try {
    const [r, dashboardCharts] = await Promise.all([
      listOrders({
        status: str('status'),
        q: str('q'),
        umkmId: str('umkm'),
        month: str('month') || todayJakarta().slice(0, 7),
        page: num('page'),
      }),
      getAdminDashboardCharts(),
    ])
    if (id !== req) return
    items.value = r.items
    total.value = r.total
    dailyOrderRows.value = dashboardCharts.pesanan_harian ?? []
  } catch (e) {
    if (id === req) error.value = e.message
  } finally {
    if (id === req) loading.value = false
  }
}
watch(() => route.query, () => { if (route.name === 'admin-pesanan') load() }, { immediate: true })
watch(() => route.query.umkm, (value) => { selectedUmkm.value = String(value ?? '') })
watch(() => route.query.month, (value) => { selectedMonth.value = String(value ?? todayJakarta().slice(0, 7)) })
onMounted(async () => {
  try {
    umkmOptions.value = await listUmkmAdmin()
  } catch (e) {
    error.value = e.message
  }
})

const namaMitra = (order) => {
  const names = [...new Set((order.order_items ?? []).map((item) => item.umkm?.name).filter(Boolean))]
  return names.length ? names.join(', ') : '—'
}
const labelPembayaran = (method) => method === 'virtual_account'
  ? 'Transfer Bank'
  : PAYMENT_METHOD[method] || method || '—'

function ubahFilter(key, value) {
  set({ [key]: value, page: 1 })
}

async function bersihkan() {
  if (!confirm('Batalkan semua pesanan yang melewati batas pembayaran dan kembalikan stoknya?')) return
  try {
    const n = await expireUnpaidOrders()
    notice.value = `${n} pesanan kedaluwarsa dibatalkan.`
    load()
  } catch (e) {
    error.value = e.message
  }
}
</script>

<template>
  <AdminPageHeader title="Pesanan" desc="Pantau dan awasi seluruh aktivitas transaksi dari semua Mitra UMKM.">
    <button class="btn-outline" type="button" @click="bersihkan">Batalkan pesanan kedaluwarsa</button>
  </AdminPageHeader>

  <section class="mb-6 rounded-xl bg-white p-5 shadow-sm ring-1 ring-line" aria-labelledby="daily-orders-title">
    <div class="flex flex-wrap items-start justify-between gap-2">
      <div>
        <h2 id="daily-orders-title" class="text-base font-semibold text-ink">Tren Pesanan Harian (7 Hari Terakhir)</h2>
        <p class="mt-1 text-sm text-muted">Jumlah pesanan masuk per hari.</p>
      </div>
    </div>
    <div v-if="loading" class="mt-4 h-40 animate-pulse rounded-lg bg-surface"></div>
    <p v-else-if="!dailyOrderRows.some((row) => Number(row.jumlah) > 0)" class="mt-4 rounded-lg bg-surface p-4 text-sm text-muted">Belum ada pesanan dalam tujuh hari terakhir.</p>
    <div v-else class="mt-4 h-[250px]">
      <Line :data="dailyOrderChartData" :options="dailyOrderChartOptions" />
    </div>
  </section>

  <div class="card p-5">
    <div class="flex flex-wrap gap-x-5 border-b border-line" role="tablist" aria-label="Filter status">
      <button
        v-for="[val, label] in tabs" :key="val" type="button" role="tab" :aria-selected="str('status') === val"
        class="-mb-px border-b-2 px-1 py-3 text-sm"
        :class="str('status') === val ? 'border-ink font-semibold text-ink' : 'border-transparent text-muted'"
        @click="set({ status: val, page: 1 })"
      >{{ label }}</button>
    </div>

    <form class="flex flex-wrap gap-2 py-4" role="search" @submit.prevent="set({ q: search.trim(), page: 1 })">
      <label for="cari-pesanan" class="sr-only">Cari nomor pesanan</label>
      <input id="cari-pesanan" v-model="search" class="input min-w-56 flex-1 sm:max-w-sm" type="search" placeholder="Cari nomor pesanan (PP-…)" />
      <label class="sr-only" for="filter-umkm">Filter Mitra UMKM</label>
      <select id="filter-umkm" v-model="selectedUmkm" class="input min-w-48" @change="ubahFilter('umkm', selectedUmkm)">
        <option value="">Semua UMKM</option>
        <option v-for="umkm in umkmOptions" :key="umkm.id" :value="umkm.id">{{ umkm.name }}</option>
      </select>
      <label class="sr-only" for="filter-bulan">Filter rentang waktu</label>
      <select id="filter-bulan" v-model="selectedMonth" class="input min-w-40" @change="ubahFilter('month', selectedMonth)">
        <option v-for="month in months" :key="month.value" :value="month.value">{{ month.value === todayJakarta().slice(0, 7) ? 'Bulan Ini' : month.label }}</option>
      </select>
      <button class="btn-primary" type="submit">Cari</button>
    </form>

    <p v-if="notice" class="mb-3 rounded-xl bg-ok-bg p-3 text-sm text-ok-fg" role="status">{{ notice }}</p>
    <p v-if="error" class="rounded-xl bg-bad-bg p-3 text-sm text-bad-fg" role="alert">
      {{ error }} <button class="ml-2 font-semibold underline" type="button" @click="load">Coba lagi</button>
    </p>
    <div v-else-if="loading" class="h-40 animate-pulse rounded-xl bg-surface"></div>
    <p v-else-if="!items.length" class="rounded-xl bg-surface p-8 text-center text-sm text-muted">Tidak ada pesanan untuk filter ini.</p>
    <div v-else class="overflow-x-auto">
      <table class="w-full min-w-[980px] text-left text-sm">
        <thead class="text-xs text-muted">
          <tr><th class="p-3 font-medium">No. pesanan</th><th class="p-3 font-medium">Pelanggan</th><th class="p-3 font-medium">Mitra UMKM</th><th class="p-3 font-medium">Tanggal</th><th class="p-3 font-medium">Total</th><th class="p-3 font-medium">Pembayaran</th><th class="p-3 font-medium">Status</th><th class="p-3"></th></tr>
        </thead>
        <tbody>
          <tr v-for="o in items" :key="o.id" class="border-t border-line">
            <td class="p-3 font-semibold">{{ o.order_no }}</td>
            <td class="p-3">{{ o.profiles?.full_name || '-' }}</td>
            <td class="max-w-56 truncate p-3" :title="namaMitra(o)">{{ namaMitra(o) }}</td>
            <td class="p-3 text-muted">{{ formatTanggalJam(o.created_at) }}</td>
            <td class="p-3">{{ formatRupiah(o.total) }}</td>
            <td class="p-3">{{ o.payment_methods?.name || labelPembayaran(o.payment_method) }}</td>
            <td class="p-3"><StatusBadge :status="o.status" /></td>
            <td class="p-3 text-right"><RouterLink :to="{ name: 'admin-pesanan-detail', params: { id: o.id } }" class="font-semibold underline">Detail</RouterLink></td>
          </tr>
        </tbody>
      </table>
    </div>
    <PaginationBar :page="num('page')" :total="total" @change="(p) => set({ page: p })" />
  </div>
</template>
