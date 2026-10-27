<script setup>
import { computed, onMounted, ref } from 'vue'
import { RouterLink, useRoute } from 'vue-router'
import ModalDialog from '@/components/ModalDialog.vue'
import OrderTracking from '@/components/OrderTracking.vue'
import { cancelOrder, confirmOrderReceived, getOrder } from '@/services/orderService'
import { useAuthStore } from '@/stores/auth'
import { formatRupiah, formatTanggalJam } from '@/lib/format'
import { ORDER_STATUS, PAYMENT_METHOD } from '@/lib/status'

const route = useRoute()
const auth = useAuthStore()
const order = ref(null)
const loading = ref(true)
const error = ref('')
const busy = ref(false)
const info = ref('')
const cancelOpen = ref(false)
const trackingRefresh = ref(0)

const addr = computed(() => order.value?.shipping_address ?? {})
const menunggu = computed(() =>
  order.value?.status === 'menunggu_pembayaran'
  || (order.value?.payment_methods?.category === 'cod'
    && order.value.payment_status !== 'dibayar'
    && order.value.status !== 'dibatalkan'),
)
const bisaDibatalkan = computed(() =>
  order.value?.status === 'menunggu_pembayaran'
  || (order.value?.status === 'diproses'
    && order.value.order_items.length > 0
    && order.value.order_items.every((item) => item.seller_shipping_status === 'menunggu_diproses')),
)
const progressSteps = ['Menunggu Pembayaran', 'Diproses / Dikemas', 'Dikirim', 'Selesai']
const progressIndex = computed(() => ({
  menunggu_pembayaran: 0,
  diproses: 1,
  dikirim: 2,
  selesai: 3,
}[order.value?.status] ?? -1))
const progressWidth = computed(() => `${Math.max(progressIndex.value, 0) / (progressSteps.length - 1) * 100}%`)

function thumbnail(item) {
  return [...(item.products?.product_images ?? [])]
    .sort((a, b) => a.sort_order - b.sort_order)[0]?.url ?? ''
}

async function load() {
  loading.value = true
  error.value = ''
  try { order.value = await getOrder(route.params.id, auth.user.id) }
  catch (e) { error.value = e.message }
  finally { loading.value = false }
}
onMounted(load)

async function aksi(fn, pesan) {
  busy.value = true
  error.value = ''
  info.value = ''
  try {
    await fn()
    info.value = pesan
    order.value = await getOrder(route.params.id, auth.user.id)
    trackingRefresh.value++
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}
const konfirmasiDiterima = () => {
  if (confirm('Konfirmasi bahwa semua barang dalam pesanan ini sudah diterima?')) {
    aksi(() => confirmOrderReceived(order.value.id), 'Penerimaan barang dikonfirmasi. Terima kasih sudah berbelanja!')
  }
}

async function batalkan() {
  if (!bisaDibatalkan.value) return
  busy.value = true
  error.value = ''
  info.value = ''
  try {
    await cancelOrder(order.value.id)
    info.value = 'Pesanan dibatalkan.'
    cancelOpen.value = false
    order.value = await getOrder(route.params.id, auth.user.id)
    trackingRefresh.value++
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <div class="min-h-screen bg-slate-50">
    <div class="mx-auto max-w-6xl px-4 pb-16 pt-6 md:px-6 lg:px-8">
      <RouterLink :to="{ name: 'pesanan' }" class="inline-flex items-center gap-2 text-sm font-medium text-slate-500 transition hover:text-emerald-700">← Semua pesanan</RouterLink>

      <div v-if="loading" class="mt-6 h-64 animate-pulse rounded-2xl bg-white shadow-sm"></div>
      <p v-else-if="error && !order" class="mt-6 rounded-xl bg-bad-bg p-4 text-sm text-bad-fg" role="alert">{{ error }}</p>
      <div v-else-if="!order" class="mt-6 rounded-2xl bg-white p-8 text-center font-semibold shadow-sm">Pesanan tidak ditemukan</div>

      <template v-else>
        <section class="mt-5 rounded-2xl bg-white p-5 shadow-sm ring-1 ring-slate-200 sm:p-7">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div>
              <p class="text-xs font-semibold uppercase tracking-wider text-slate-400">Detail pesanan</p>
              <h1 class="mt-1 text-xl font-bold text-slate-900 sm:text-2xl">{{ order.order_no }}</h1>
            </div>
            <span class="rounded-full px-3 py-1.5 text-xs font-semibold" :class="ORDER_STATUS[order.status]?.cls">{{ ORDER_STATUS[order.status]?.label || order.status }}</span>
          </div>

          <div v-if="order.status === 'dibatalkan'" class="mt-6 rounded-xl border border-red-100 bg-red-50 p-4 text-sm font-medium text-red-800" role="status">
            Pesanan ini telah dibatalkan.
          </div>
          <div v-else class="relative mt-8">
            <div class="absolute left-[12.5%] right-[12.5%] top-4 h-1 rounded-full bg-slate-100" aria-hidden="true">
              <div class="h-full rounded-full bg-emerald-600 transition-all duration-500" :style="{ width: progressWidth }"></div>
            </div>
            <ol class="relative grid grid-cols-4">
              <li v-for="(step, index) in progressSteps" :key="step" class="flex flex-col items-center px-1 text-center">
                <span
                  class="z-10 flex h-8 w-8 items-center justify-center rounded-full border-2 text-xs font-bold transition-colors"
                  :class="index <= progressIndex ? 'border-emerald-600 bg-emerald-600 text-white' : 'border-slate-200 bg-white text-slate-400'"
                >
                  <svg v-if="index < progressIndex" viewBox="0 0 20 20" class="h-4 w-4" fill="currentColor" aria-hidden="true"><path fill-rule="evenodd" d="M16.704 5.29a1 1 0 0 1 .006 1.414l-7.1 7.16a1 1 0 0 1-1.42.006l-3.9-3.84a1 1 0 0 1 1.404-1.426l3.19 3.14 6.4-6.448a1 1 0 0 1 1.42-.006Z" clip-rule="evenodd" /></svg>
                  <span v-else>{{ index + 1 }}</span>
                </span>
                <span class="mt-2 max-w-24 text-[10px] font-medium leading-4 sm:max-w-none sm:text-xs" :class="index <= progressIndex ? 'text-emerald-800' : 'text-slate-400'">{{ step }}</span>
              </li>
            </ol>
          </div>
        </section>

        <p v-if="info" class="mt-4 rounded-xl border border-emerald-100 bg-emerald-50 p-3 text-sm text-emerald-800" role="status">{{ info }}</p>
        <p v-if="error" class="mt-4 rounded-xl border border-red-100 bg-red-50 p-3 text-sm text-red-700" role="alert">{{ error }}</p>

        <section v-if="menunggu" class="mt-5 rounded-2xl border border-amber-100 bg-amber-50 p-5">
          <div>
            <p class="font-semibold text-amber-950">{{ order.payment_methods?.category === 'cod' || order.payment_method === 'cod' ? 'Pesanan COD' : 'Pesanan menunggu pembayaran' }} · {{ formatRupiah(order.total) }}</p>
            <p class="mt-1 text-sm text-amber-800">Metode yang dipilih: {{ order.payment_methods?.name || PAYMENT_METHOD[order.payment_method] || order.payment_method }}. {{ order.payment_methods?.category === 'cod' || order.payment_method === 'cod' ? 'Siapkan pembayaran tunai saat pesanan diterima.' : 'Pesanan akan diproses setelah pembayaran terkonfirmasi.' }}</p>
          </div>
        </section>
        <section v-if="bisaDibatalkan" class="mt-5 flex flex-wrap items-center justify-between gap-4 rounded-2xl border border-red-100 bg-red-50 p-5">
          <p class="text-sm text-red-800">Pesanan masih menunggu pembayaran atau belum mulai diproses oleh toko.</p>
          <button class="rounded-lg border border-red-200 bg-white px-4 py-2.5 text-sm font-semibold text-red-800 transition hover:bg-red-100 disabled:opacity-50" type="button" :disabled="busy" @click="cancelOpen = true">Batalkan pesanan</button>
        </section>

        <div class="mt-5 grid items-start gap-5 lg:grid-cols-[minmax(0,1fr)_360px]">
          <div class="space-y-5">
            <section class="overflow-hidden rounded-2xl bg-white shadow-sm ring-1 ring-slate-200">
              <div class="border-b border-slate-100 px-5 py-4 sm:px-6">
                <h2 class="font-semibold text-slate-900">Produk dalam pesanan</h2>
                <p class="mt-1 text-xs text-slate-500">{{ order.order_items.length }} item · Dipesan {{ formatTanggalJam(order.created_at) }}</p>
              </div>
              <ul class="divide-y divide-slate-100 px-5 sm:px-6">
                <li v-for="item in order.order_items" :key="item.id" class="grid grid-cols-[64px_minmax(0,1fr)_auto] items-center gap-3 py-4 sm:grid-cols-[76px_minmax(0,1fr)_auto] sm:gap-4">
                  <div class="h-16 w-16 overflow-hidden rounded-xl bg-slate-100 sm:h-[76px] sm:w-[76px]">
                    <img v-if="thumbnail(item)" :src="thumbnail(item)" :alt="item.product_name" class="h-full w-full object-cover" />
                    <div v-else class="flex h-full w-full items-center justify-center text-slate-300" aria-label="Foto produk tidak tersedia">
                      <svg viewBox="0 0 24 24" class="h-7 w-7" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true">
                        <rect x="3" y="4" width="18" height="16" rx="2" /><circle cx="8.5" cy="9" r="1.5" /><path stroke-linecap="round" stroke-linejoin="round" d="m21 15-5-5L5 20" />
                      </svg>
                    </div>
                  </div>
                  <div class="min-w-0">
                    <p class="line-clamp-2 text-sm font-semibold text-slate-900">{{ item.product_name }}</p>
                    <p class="mt-1 text-xs text-slate-500">Harga satuan {{ formatRupiah(item.unit_price) }}</p>
                    <p class="mt-1 text-xs text-slate-500">Jumlah {{ item.quantity }}</p>
                  </div>
                  <p class="whitespace-nowrap text-right text-sm font-semibold text-slate-900">{{ formatRupiah(item.unit_price * item.quantity) }}</p>
                </li>
              </ul>
              <dl class="space-y-2 border-t border-slate-100 bg-slate-50/70 px-5 py-4 text-sm sm:px-6">
                <div class="flex justify-between"><dt class="text-slate-500">Subtotal produk</dt><dd class="font-medium text-slate-800">{{ formatRupiah(order.subtotal) }}</dd></div>
                <div class="flex justify-between"><dt class="text-slate-500">Ongkos kirim</dt><dd class="font-medium text-slate-800">{{ formatRupiah(order.shipping_cost) }}</dd></div>
                <div class="flex justify-between border-t border-slate-200 pt-3 text-base font-bold"><dt>Total pembayaran</dt><dd class="text-emerald-800">{{ formatRupiah(order.total) }}</dd></div>
              </dl>
            </section>

            <OrderTracking :key="trackingRefresh" :order-id="order.id" user-role="buyer" compact />
          </div>

          <aside class="space-y-5 lg:sticky lg:top-5">
            <section class="rounded-2xl bg-white p-5 shadow-sm ring-1 ring-slate-200">
              <div class="flex items-center gap-2.5">
                <span class="flex h-9 w-9 items-center justify-center rounded-full bg-emerald-50 text-emerald-700" aria-hidden="true">
                  <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="1.8">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M20 10c0 5-8 11-8 11S4 15 4 10a8 8 0 1 1 16 0Z" /><circle cx="12" cy="10" r="2.5" />
                  </svg>
                </span>
                <h2 class="font-semibold text-slate-900">Dikirim ke</h2>
              </div>
              <p class="mt-4 text-sm font-semibold text-slate-900">{{ addr.recipient_name }} <span class="font-normal text-slate-500">· {{ addr.phone }}</span></p>
              <p class="mt-1 text-sm leading-6 text-slate-600">{{ addr.street }}, {{ addr.city }}, {{ addr.province }} {{ addr.postal_code }}</p>
            </section>

            <section v-if="order.status === 'dikirim'" class="rounded-2xl border border-emerald-100 bg-emerald-50 p-5">
              <p class="text-sm font-semibold text-emerald-950">Paket sudah sampai?</p>
              <p class="mt-1 text-xs leading-5 text-emerald-800">Konfirmasikan setelah Anda menerima seluruh barang dalam pesanan.</p>
              <button class="mt-4 w-full rounded-lg bg-emerald-700 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-emerald-800 disabled:opacity-50" type="button" :disabled="busy" @click="konfirmasiDiterima">
                {{ busy ? 'Memproses...' : 'Konfirmasi Penerimaan Barang' }}
              </button>
            </section>
            <section v-else-if="order.status === 'selesai'" class="rounded-2xl border border-emerald-100 bg-emerald-50 p-5">
              <p class="text-sm font-semibold text-emerald-950">Pesanan selesai</p>
              <p class="mt-1 text-xs leading-5 text-emerald-800">Terima kasih telah mendukung mitra UMKM PasarPintar.</p>
              <RouterLink :to="{ name: 'katalog' }" class="mt-4 inline-flex w-full items-center justify-center rounded-lg border border-emerald-200 bg-white px-4 py-2.5 text-sm font-semibold text-emerald-800 transition hover:bg-emerald-100">Belanja lagi</RouterLink>
            </section>
          </aside>
        </div>
      </template>
    </div>

    <ModalDialog :open="cancelOpen" title="Batalkan pesanan?" @close="cancelOpen = false">
      <div class="space-y-4">
        <p class="text-sm leading-6 text-slate-600">
          Apakah Anda yakin ingin membatalkan pesanan <strong class="text-slate-900">{{ order?.order_no }}</strong>?
          Tindakan ini tidak dapat dibatalkan.
        </p>
        <div class="flex justify-end gap-2">
          <button class="btn-outline" type="button" :disabled="busy" @click="cancelOpen = false">Kembali</button>
          <button class="rounded-lg bg-red-700 px-4 py-2 text-sm font-semibold text-white transition hover:bg-red-800 disabled:opacity-50" type="button" :disabled="busy" @click="batalkan">
            {{ busy ? 'Membatalkan…' : 'Ya, batalkan' }}
          </button>
        </div>
      </div>
    </ModalDialog>
  </div>
</template>
