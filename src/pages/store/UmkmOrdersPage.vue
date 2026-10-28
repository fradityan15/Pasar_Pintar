<script setup>
import { computed, onMounted, ref } from 'vue'
import SellerDashboardSidebar from '@/components/SellerDashboardSidebar.vue'
import OrderTracking from '@/components/OrderTracking.vue'
import { getMyUmkm } from '@/services/umkmPartnerService'
import { listSellerOrders, processSellerOrder, shipSellerOrder } from '@/services/sellerOrderService'
import { formatRupiah, formatTanggalJam } from '@/lib/format'
import { ORDER_STATUS } from '@/lib/status'

const umkm = ref(null)
const orders = ref([])
const loading = ref(true)
const error = ref('')
const notice = ref('')
const busyOrderId = ref(null)
const expandedOrderId = ref(null)
const trackingRefresh = ref(0)
const canManageOrders = computed(() => umkm.value?.status === 'active' && umkm.value.is_active)

async function load() {
  loading.value = true
  error.value = ''
  try {
    umkm.value = await getMyUmkm()
    orders.value = canManageOrders.value ? await listSellerOrders(umkm.value.id) : []
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

onMounted(load)

async function ubahStatus(order, action, successMessage) {
  busyOrderId.value = order.order_id
  error.value = ''
  notice.value = ''
  try {
    await action(order.order_id, umkm.value.id)
    notice.value = `Pesanan ${order.order_no} ${successMessage}.`
    trackingRefresh.value++
    await load()
  } catch (e) {
    error.value = e.message
  } finally {
    busyOrderId.value = null
  }
}
</script>

<template>
  <div class="min-h-full bg-slate-50 lg:flex">
    <SellerDashboardSidebar :umkm="umkm" />

    <main class="min-w-0 flex-1 px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
      <div class="mx-auto max-w-7xl">
        <div>
          <p class="text-sm font-medium text-emerald-700">Dasbor penjual</p>
          <h1 class="mt-1 text-2xl font-bold tracking-tight text-slate-900 sm:text-3xl">Daftar Pesanan Masuk</h1>
          <p class="mt-1.5 text-sm text-slate-500">Pantau dan kelola pesanan untuk produk toko {{ umkm?.name || 'Anda' }}.</p>
        </div>

        <p v-if="notice" class="mt-5 rounded-xl border border-emerald-100 bg-emerald-50 p-3 text-sm text-emerald-800" role="status">{{ notice }}</p>
        <p v-if="error" class="mt-5 rounded-xl border border-red-100 bg-red-50 p-4 text-sm text-red-700" role="alert">
          {{ error }}
          <button class="ml-1 font-semibold underline" type="button" @click="load">Coba lagi</button>
        </p>

        <div v-if="loading" class="mt-6 space-y-3">
          <div v-for="n in 3" :key="n" class="h-24 animate-pulse rounded-xl bg-white shadow-sm ring-1 ring-slate-200"></div>
        </div>
        <div v-else-if="!umkm" class="mt-6 rounded-xl border border-slate-200 bg-white p-6">
          <p class="font-semibold text-slate-900">Data UMKM tidak ditemukan.</p>
        </div>
        <div v-else-if="!canManageOrders" class="mt-6 rounded-xl border border-amber-200 bg-amber-50 p-5 text-sm text-amber-900" role="status">
          Fitur pesanan masuk tersedia setelah pendaftaran UMKM disetujui dan toko diaktifkan.
        </div>
        <section v-else class="mt-6 overflow-hidden rounded-xl bg-white shadow-sm ring-1 ring-slate-200">
          <div class="border-b border-slate-100 px-5 py-4 sm:px-6">
            <h2 class="font-semibold text-slate-900">Pesanan Toko</h2>
            <p class="mt-1 text-sm text-slate-500">Nilai pesanan hanya mencakup produk dari toko Anda.</p>
          </div>

          <div v-if="!orders.length" class="px-6 py-14 text-center">
            <p class="font-semibold text-slate-900">Belum ada pesanan masuk</p>
            <p class="mt-1 text-sm text-slate-500">Pesanan untuk produk toko akan muncul di sini.</p>
          </div>

          <div v-else class="w-full overflow-x-auto">
            <table class="w-full min-w-[850px] text-left text-sm">
              <thead class="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
                <tr>
                  <th class="px-5 py-3 font-semibold sm:px-6">ID Pesanan</th>
                  <th class="px-5 py-3 font-semibold">Pembeli & Produk</th>
                  <th class="px-5 py-3 font-semibold">Total Harga</th>
                  <th class="px-5 py-3 font-semibold">Status</th>
                  <th class="px-5 py-3 font-semibold">Tanggal</th>
                  <th class="px-5 py-3 font-semibold">Aksi</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="order in orders" :key="order.order_id" class="border-t border-slate-100 align-top">
                  <td class="whitespace-nowrap px-5 py-4 font-semibold text-slate-900 sm:px-6">{{ order.order_no }}</td>
                  <td class="min-w-64 px-5 py-4">
                    <p class="font-medium text-slate-900">{{ order.customer_name }}</p>
                    <ul class="mt-1 space-y-1 text-xs text-slate-500">
                      <li v-for="(item, index) in order.products" :key="`${order.order_id}-${index}`">
                        {{ item.product_name }} × {{ item.quantity }}
                      </li>
                    </ul>
                  </td>
                  <td class="whitespace-nowrap px-5 py-4 font-bold text-gray-900">{{ formatRupiah(order.total) }}</td>
                  <td class="whitespace-nowrap px-5 py-4">
                    <span class="inline-flex rounded-full px-2.5 py-1 text-xs font-semibold" :class="ORDER_STATUS[order.status]?.cls || 'bg-slate-100 text-slate-700'">
                      {{ order.status === 'menunggu_pembayaran'
                        ? ORDER_STATUS[order.status]?.label
                        : (order.seller_shipping_status === 'menunggu_diproses' ? 'Siap diproses' : (ORDER_STATUS[order.status]?.label || order.status)) }}
                    </span>
                  </td>
                  <td class="whitespace-nowrap px-5 py-4 text-slate-500">{{ formatTanggalJam(order.created_at) }}</td>
                  <td class="whitespace-nowrap px-5 py-4">
                    <div class="flex items-center gap-2">
                      <button class="rounded-lg border border-slate-200 px-3 py-2 text-xs font-semibold text-slate-700 hover:bg-slate-50" type="button" @click="expandedOrderId = expandedOrderId === order.order_id ? null : order.order_id">
                        {{ expandedOrderId === order.order_id ? 'Tutup riwayat' : 'Riwayat' }}
                      </button>
                      <div
                        v-if="(order.payment_status === 'dibayar' || order.payment_category === 'cod')
                          && ['menunggu_diproses', 'diproses'].includes(order.status)
                          && (order.seller_shipping_status === 'menunggu_diproses' || order.seller_shipping_status === 'diproses')"
                        class="flex gap-2"
                      >
                        <button
                          v-if="order.seller_shipping_status === 'menunggu_diproses'"
                          class="rounded-lg bg-gray-900 px-3 py-2 text-xs font-semibold text-white transition hover:bg-black disabled:cursor-wait disabled:opacity-60"
                          type="button"
                          :disabled="busyOrderId === order.order_id"
                          @click="ubahStatus(order, processSellerOrder, 'mulai diproses')"
                        >{{ busyOrderId === order.order_id ? 'Memproses...' : 'Terima & Proses Pesanan' }}</button>
                        <button
                          v-else
                          class="rounded-lg bg-gray-900 px-3 py-2 text-xs font-semibold text-white transition hover:bg-black disabled:cursor-wait disabled:opacity-60"
                          type="button"
                          :disabled="busyOrderId === order.order_id"
                          @click="ubahStatus(order, shipSellerOrder, 'ditandai sudah dikirim')"
                        >{{ busyOrderId === order.order_id ? 'Memproses...' : 'Kirim Pesanan' }}</button>
                      </div>
                      <span v-else class="text-xs text-slate-400">—</span>
                    </div>
                  </td>
                </tr>
                <tr v-for="order in orders.filter((item) => item.order_id === expandedOrderId)" :key="`${order.order_id}-tracking`" class="border-t border-slate-100 bg-slate-50">
                  <td colspan="6" class="p-4 sm:p-6">
                    <OrderTracking :key="`${order.order_id}-${trackingRefresh}`" :order-id="order.order_id" user-role="seller" />
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <p class="border-t border-slate-100 px-5 py-3 text-xs text-slate-500 sm:px-6">
            Aksi hanya tersedia setelah pembayaran berhasil. Proses dan status pengiriman dikelola per toko.
          </p>
        </section>
      </div>
    </main>
  </div>
</template>
