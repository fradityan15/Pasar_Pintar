<script setup>
import { computed, onMounted, ref } from 'vue'
import AdminPageHeader from '@/components/AdminPageHeader.vue'
import SalesChart from '@/components/SalesChart.vue'
import StatCard from '@/components/StatCard.vue'
import { salesReport, topProducts } from '@/services/adminReportService'
import { addDays, downloadCsv, todayJakarta } from '@/lib/csv'
import { formatRupiah } from '@/lib/format'

const today = todayJakarta()
const from = ref(addDays(today, -29))
const to = ref(today)
const rows = ref([])
const top = ref([])
const loading = ref(true)
const error = ref('')

const totalOmzet = computed(() => rows.value.reduce((s, r) => s + Number(r.omzet), 0))
const totalPesanan = computed(() => rows.value.reduce((s, r) => s + Number(r.jumlah_pesanan), 0))
const rata = computed(() => (totalPesanan.value ? totalOmzet.value / totalPesanan.value : 0))

async function load() {
  if (from.value > to.value) { error.value = 'Tanggal awal tidak boleh setelah tanggal akhir.'; return }
  if (new Date(to.value) - new Date(from.value) > 366 * 86400000) { error.value = 'Rentang maksimal 366 hari.'; return }
  loading.value = true
  error.value = ''
  try {
    ;[rows.value, top.value] = await Promise.all([salesReport(from.value, to.value), topProducts(from.value, to.value)])
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}
onMounted(load)

function preset(days) {
  to.value = today
  from.value = addDays(today, -(days - 1))
  load()
}
function bulanIni() {
  from.value = today.slice(0, 8) + '01'
  to.value = today
  load()
}
const unduh = () =>
  downloadCsv(`laporan-penjualan_${from.value}_${to.value}.csv`, ['Tanggal', 'Jumlah pesanan', 'Omzet (Rp)'],
    rows.value.map((r) => [r.tanggal, r.jumlah_pesanan, r.omzet]))
</script>

<template>
  <AdminPageHeader title="Laporan penjualan" desc="Dihitung dari pesanan yang sudah dibayar dan tidak dibatalkan.">
    <button class="btn-outline" type="button" :disabled="!rows.length" @click="unduh">Unduh CSV</button>
  </AdminPageHeader>

  <form class="card mb-4 flex flex-wrap items-end gap-3 p-4" @submit.prevent="load">
    <div><label for="dari" class="mb-1.5 block text-sm font-medium">Dari</label><input id="dari" v-model="from" class="input" type="date" required /></div>
    <div><label for="sampai" class="mb-1.5 block text-sm font-medium">Sampai</label><input id="sampai" v-model="to" class="input" type="date" required /></div>
    <button class="btn-primary" type="submit" :disabled="loading">Tampilkan</button>
    <div class="ml-auto flex gap-2">
      <button class="btn-outline" type="button" @click="preset(7)">7 hari</button>
      <button class="btn-outline" type="button" @click="preset(30)">30 hari</button>
      <button class="btn-outline" type="button" @click="bulanIni">Bulan ini</button>
    </div>
  </form>

  <p v-if="error" class="mb-4 rounded-xl bg-bad-bg p-3 text-sm text-bad-fg" role="alert">{{ error }}</p>
  <div v-if="loading" class="h-64 animate-pulse rounded-xl bg-white"></div>

  <template v-else-if="rows.length">
    <div class="grid gap-4 sm:grid-cols-3">
      <StatCard label="Total omzet" :value="formatRupiah(totalOmzet)" />
      <StatCard label="Jumlah pesanan" :value="totalPesanan" />
      <StatCard label="Rata-rata per pesanan" :value="formatRupiah(rata)" />
    </div>

    <section class="card mt-4 p-5">
      <h2 class="text-base font-semibold">Omzet harian</h2>
      <SalesChart :data="rows" />
    </section>

    <div class="mt-4 grid gap-4 lg:grid-cols-2">
      <section class="card p-5">
        <h2 class="text-base font-semibold">Produk terlaris</h2>
        <p v-if="!top.length" class="mt-3 text-sm text-muted">Belum ada penjualan pada rentang ini.</p>
        <ol v-else class="mt-3 flex flex-col gap-2 text-sm">
          <li v-for="(p, i) in top" :key="p.name" class="flex justify-between gap-3">
            <span>{{ i + 1 }}. {{ p.name }}</span><span class="text-muted">{{ p.qty }} terjual · {{ formatRupiah(p.revenue) }}</span>
          </li>
        </ol>
      </section>

      <section class="card max-h-80 overflow-y-auto p-4 md:p-5">
        <h2 class="text-base font-semibold">Rincian per hari</h2>
        <div class="mt-3 w-full overflow-x-auto">
          <table class="min-w-[360px] w-full text-left text-sm">
            <thead class="text-xs text-muted"><tr><th class="py-2 font-medium">Tanggal</th><th class="py-2 font-medium">Pesanan</th><th class="py-2 text-right font-medium">Omzet</th></tr></thead>
            <tbody>
              <tr v-for="r in [...rows].reverse()" :key="r.tanggal" class="border-t border-line">
                <td class="py-2">{{ r.tanggal }}</td><td class="py-2">{{ r.jumlah_pesanan }}</td><td class="py-2 text-right">{{ formatRupiah(r.omzet) }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </div>
  </template>
</template>
