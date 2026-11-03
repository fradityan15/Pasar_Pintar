<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { RouterLink, useRoute, useRouter } from 'vue-router'
import { getLatestPayment, getOrder } from '@/services/orderService'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import { formatRupiah, formatTanggalJam } from '@/lib/format'

const route = useRoute()
const router = useRouter()
const auth = useAuthStore()
const order = ref(null)
const payment = ref(null)
const loading = ref(true)
const error = ref('')
const paymentError = ref('')
const checking = ref(false)
const now = ref(Date.now())
let countdownTimer
let statusTimer
let polling = false

const paymentMethod = computed(() => order.value?.payment_methods)
const isGateway = computed(() => paymentMethod.value?.provider === 'midtrans')
const isCod = computed(() => order.value?.payment_method === 'cod' || paymentMethod.value?.category === 'cod')
const isPaid = computed(() => order.value?.payment_status === 'dibayar')
const isWaitingForCod = computed(() => isCod.value && !isPaid.value && order.value?.status !== 'dibatalkan')
const expiry = computed(() => payment.value?.expires_at || order.value?.payment_expires_at)
const expiryTime = computed(() => expiry.value ? new Date(expiry.value).getTime() : null)
const remainingSeconds = computed(() => expiryTime.value ? Math.max(0, Math.floor((expiryTime.value - now.value) / 1000)) : 0)
const isExpired = computed(() => !isCod.value && (
  ['dibatalkan', 'kedaluwarsa'].includes(order.value?.status) ||
  payment.value?.status === 'expired' ||
  (expiryTime.value !== null && remainingSeconds.value === 0)
))
const countdown = computed(() => {
  const hours = Math.floor(remainingSeconds.value / 3600)
  const minutes = Math.floor((remainingSeconds.value % 3600) / 60)
  const seconds = remainingSeconds.value % 60
  return [hours, minutes, seconds].map((part) => String(part).padStart(2, '0')).join(':')
})
const instructions = computed(() => payment.value?.instructions ?? {})

async function load() {
  loading.value = true
  error.value = ''
  try {
    order.value = await getOrder(route.params.orderId, auth.user.id)
    if (!order.value) {
      error.value = 'Pesanan tidak ditemukan atau tidak dapat diakses.'
      return
    }
    if (isGateway.value && !isPaid.value) await requestGatewayPayment()
  } catch (e) {
    error.value = e.message || 'Pesanan tidak dapat dimuat.'
  } finally {
    loading.value = false
  }
}

async function requestGatewayPayment() {
  if (!order.value || !isGateway.value || isPaid.value) return
  paymentError.value = ''
  try {
    const { data, error: invokeError } = await supabase.functions.invoke('create-payment', {
      body: { order_id: order.value.id },
    })
    if (invokeError || !data) {
      throw new Error('Instruksi pembayaran belum tersedia. Periksa status beberapa saat lagi.')
    }
    payment.value = data
  } catch (e) {
    paymentError.value = e.message || 'Instruksi pembayaran belum tersedia.'
    try {
      payment.value = await getLatestPayment(order.value.id)
    } catch (statusError) {
      console.error('Status pembayaran Midtrans tidak dapat dibaca:', statusError)
    }
  }
}

async function refreshStatus() {
  if (!order.value || checking.value) return
  checking.value = true
  error.value = ''
  try {
    if (isGateway.value) await requestGatewayPayment()
    const latestOrder = await getOrder(route.params.orderId, auth.user.id)
    if (!latestOrder) throw new Error('Pesanan tidak ditemukan atau tidak dapat diakses.')
    order.value = latestOrder
    if (isGateway.value) payment.value = await getLatestPayment(latestOrder.id)
    if (latestOrder.payment_status === 'dibayar') {
      await router.replace({ name: 'pesanan-detail', params: { id: latestOrder.id } })
    }
  } catch (e) {
    error.value = e.message || 'Status pembayaran tidak dapat diperbarui.'
  } finally {
    checking.value = false
  }
}

async function pollPaymentStatus() {
  if (polling || !isGateway.value || !order.value || isPaid.value || isExpired.value) return
  polling = true
  try {
    const [latestOrder, latestPayment] = await Promise.all([
      getOrder(route.params.orderId, auth.user.id),
      getLatestPayment(order.value.id),
    ])
    if (latestOrder) order.value = latestOrder
    payment.value = latestPayment
    if (latestOrder?.payment_status === 'dibayar') {
      await router.replace({ name: 'pesanan-detail', params: { id: latestOrder.id } })
    }
  } catch (e) {
    console.error('Polling status pembayaran gagal:', e)
  } finally {
    polling = false
  }
}

onMounted(async () => {
  await load()
  countdownTimer = window.setInterval(() => { now.value = Date.now() }, 1000)
  statusTimer = window.setInterval(pollPaymentStatus, 5000)
})

onBeforeUnmount(() => {
  window.clearInterval(countdownTimer)
  window.clearInterval(statusTimer)
})
</script>

<template>
  <div class="min-h-screen bg-slate-50">
    <div class="mx-auto max-w-3xl px-4 pb-16 pt-8 md:px-6 lg:px-8">
      <RouterLink :to="{ name: 'pesanan' }" class="inline-flex items-center gap-2 text-sm font-medium text-slate-500 transition hover:text-gray-900">
        <span aria-hidden="true">←</span> Pesanan saya
      </RouterLink>

      <div v-if="loading" class="mt-6 space-y-4">
        <div class="h-48 animate-pulse rounded-2xl bg-white shadow-sm"></div>
        <div class="h-72 animate-pulse rounded-2xl bg-white shadow-sm"></div>
      </div>
      <section v-else-if="error && !order" class="mt-6 rounded-2xl bg-white p-6 text-center shadow-sm sm:p-10">
        <p class="font-semibold text-red-700" role="alert">{{ error }}</p>
        <button class="btn-outline mt-5" type="button" @click="load">Coba lagi</button>
      </section>
      <template v-else-if="order">
        <header class="mt-6 rounded-2xl bg-white p-5 shadow-sm ring-1 ring-slate-200 sm:p-7">
          <p class="text-sm font-medium text-indigo-700">{{ isPaid ? 'Pembayaran terkonfirmasi' : isCod ? 'Pesanan berhasil dibuat' : 'Selesaikan pembayaran Anda' }}</p>
          <h1 class="mt-1 text-2xl font-bold tracking-tight text-slate-900 sm:text-3xl">
            {{ isPaid ? 'Pembayaran Berhasil' : isExpired ? 'Batas Pembayaran Berakhir' : isCod ? 'Instruksi Pembayaran COD' : 'Menunggu Pembayaran' }}
          </h1>
          <p class="mt-2 text-sm text-slate-500">Pesanan {{ order.order_no }}</p>
          <div class="mt-6 flex flex-wrap items-end justify-between gap-4 border-t border-slate-100 pt-5">
            <div>
              <p class="text-sm text-slate-500">{{ isCod ? 'Total yang dibayarkan kepada kurir' : 'Total tagihan' }}</p>
              <p class="mt-1 text-3xl font-bold tracking-tight text-gray-900">{{ formatRupiah(order.total) }}</p>
            </div>
            <div v-if="!isCod && !isPaid && expiry" class="rounded-xl bg-amber-50 px-4 py-3 text-right">
              <p class="text-xs font-medium text-amber-800">Bayar sebelum {{ formatTanggalJam(expiry) }}</p>
              <p class="mt-1 font-mono text-lg font-bold tabular-nums text-amber-950" role="timer" aria-label="Sisa waktu pembayaran">{{ countdown }}</p>
            </div>
          </div>
        </header>

        <section class="mt-5 rounded-2xl bg-white p-5 shadow-sm ring-1 ring-slate-200 sm:p-7">
          <div class="border-b border-slate-100 pb-4">
            <h2 class="font-semibold text-slate-900">{{ paymentMethod?.name || 'Metode pembayaran' }}</h2>
            <p class="mt-0.5 text-xs text-slate-500">{{ isGateway ? 'Instruksi pembayaran Midtrans Sandbox' : 'Instruksi pembayaran' }}</p>
          </div>

          <div v-if="isPaid" class="mt-5 rounded-xl border border-indigo-100 bg-indigo-50 p-4 text-sm leading-6 text-indigo-900" role="status">
            Pembayaran pesanan ini sudah dikonfirmasi. Pesanan sedang diteruskan untuk diproses.
          </div>
          <div v-else-if="isExpired" class="mt-5 rounded-xl border border-red-100 bg-red-50 p-4 text-sm leading-6 text-red-800" role="alert">
            Batas waktu pembayaran telah berakhir. Jangan lanjutkan pembayaran. Jika transaksi terlambat terbayar, hubungi pengelola toko untuk rekonsiliasi.
          </div>
          <div v-else-if="isCod" class="mt-5 rounded-xl border border-slate-200 bg-slate-50 p-5">
            <p class="font-semibold text-slate-900">Bayar saat pesanan diterima</p>
            <p class="mt-2 text-sm leading-6 text-slate-600">Siapkan pembayaran sebesar <span class="font-bold text-gray-900">{{ formatRupiah(order.total) }}</span> untuk kurir saat barang tiba.</p>
          </div>
          <div v-else-if="isGateway && paymentMethod?.category === 'qris'" class="mt-5 flex flex-col items-center rounded-xl border border-slate-200 bg-slate-50 p-5 text-center">
            <p class="text-sm leading-6 text-slate-600">Pindai QRIS berikut. Pembayaran dikonfirmasi otomatis setelah notifikasi Midtrans tervalidasi.</p>
            <img v-if="instructions.qr_url" :src="instructions.qr_url" :alt="`Kode QRIS pembayaran ${paymentMethod.name}`" class="mt-5 max-h-80 max-w-full rounded-xl bg-white p-2 object-contain shadow-sm ring-1 ring-slate-200" />
            <p v-else class="mt-4 text-sm text-amber-800" role="status">Menyiapkan atau memeriksa transaksi pembayaran…</p>
            <p class="mt-4 text-xs text-slate-500">Nominal: {{ formatRupiah(payment?.amount ?? order.total) }}</p>
          </div>
          <div v-else-if="isGateway && paymentMethod?.category === 'va'" class="mt-5 rounded-xl border border-slate-200 bg-slate-50 p-5">
            <p class="text-sm leading-6 text-slate-600">Transfer ke Virtual Account unik berikut. Pembayaran dikonfirmasi otomatis.</p>
            <dl v-if="instructions.va_number || instructions.bill_key" class="mt-4 divide-y divide-slate-200 rounded-xl border border-slate-200 bg-white px-4">
              <div class="flex flex-wrap justify-between gap-2 py-3 text-sm"><dt class="text-slate-500">Bank</dt><dd class="font-semibold uppercase text-slate-900">{{ instructions.bank }}</dd></div>
              <div v-if="instructions.biller_code" class="flex flex-wrap justify-between gap-2 py-3 text-sm"><dt class="text-slate-500">Kode perusahaan</dt><dd class="font-mono font-semibold tracking-wide text-slate-900">{{ instructions.biller_code }}</dd></div>
              <div class="flex flex-wrap justify-between gap-2 py-3 text-sm"><dt class="text-slate-500">{{ instructions.bill_key ? 'Kode pembayaran' : 'Nomor Virtual Account' }}</dt><dd class="font-mono font-semibold tracking-wide text-slate-900">{{ instructions.bill_key || instructions.va_number }}</dd></div>
              <div class="flex flex-wrap justify-between gap-2 py-3 text-sm"><dt class="text-slate-500">Total</dt><dd class="font-semibold text-slate-900">{{ formatRupiah(payment?.amount ?? order.total) }}</dd></div>
            </dl>
            <p v-else class="mt-4 text-sm text-amber-800" role="status">Menyiapkan atau memeriksa transaksi Virtual Account…</p>
          </div>
          <div v-else-if="!isGateway && paymentMethod?.category === 'qris'" class="mt-5 flex flex-col items-center rounded-xl border border-slate-200 bg-slate-50 p-5 text-center">
            <p class="text-sm leading-6 text-slate-600">Pindai kode QR berikut melalui aplikasi mobile banking atau dompet digital Anda.</p>
            <img v-if="paymentMethod.qr_image_url" :src="paymentMethod.qr_image_url" :alt="`Kode QR pembayaran ${paymentMethod.name}`" class="mt-5 max-h-80 max-w-full rounded-xl bg-white p-2 object-contain shadow-sm ring-1 ring-slate-200" />
            <p v-else class="mt-4 text-sm text-red-700" role="alert">Kode QR belum tersedia. Silakan hubungi pengelola toko.</p>
            <p class="mt-4 text-xs text-slate-500">Transfer manual akan diverifikasi oleh admin.</p>
          </div>
          <div v-else-if="!isGateway && ['va', 'bank_transfer'].includes(paymentMethod?.category)" class="mt-5 rounded-xl border border-slate-200 bg-slate-50 p-5">
            <p class="text-sm leading-6 text-slate-600">Silakan transfer tepat sesuai total tagihan ke rekening berikut.</p>
            <dl class="mt-4 divide-y divide-slate-200 rounded-xl border border-slate-200 bg-white px-4">
              <div class="flex flex-wrap justify-between gap-2 py-3 text-sm"><dt class="text-slate-500">Bank</dt><dd class="font-semibold text-slate-900">{{ paymentMethod.name }}</dd></div>
              <div class="flex flex-wrap justify-between gap-2 py-3 text-sm"><dt class="text-slate-500">Nomor rekening</dt><dd class="font-mono font-semibold tracking-wide text-slate-900">{{ paymentMethod.account_number || 'Belum tersedia' }}</dd></div>
              <div class="flex flex-wrap justify-between gap-2 py-3 text-sm"><dt class="text-slate-500">Atas nama</dt><dd class="font-semibold text-slate-900">{{ paymentMethod.account_name || 'Belum tersedia' }}</dd></div>
            </dl>
            <p class="mt-3 text-xs leading-5 text-slate-500">Transfer manual diteruskan ke admin untuk diverifikasi.</p>
          </div>

          <p v-if="error" class="mt-4 rounded-xl bg-red-50 p-3 text-sm text-red-700" role="alert">{{ error }}</p>
          <p v-if="paymentError" class="mt-4 rounded-xl bg-amber-50 p-3 text-sm text-amber-900" role="status">{{ paymentError }}</p>
          <div class="mt-6 border-t border-slate-100 pt-5">
            <RouterLink v-if="isPaid || isExpired" :to="{ name: 'pesanan-detail', params: { id: order.id } }" class="btn w-full bg-gray-900 text-white transition-colors hover:bg-black hover:shadow-md">Lihat detail pesanan</RouterLink>
            <RouterLink v-else-if="isWaitingForCod" :to="{ name: 'pesanan-detail', params: { id: order.id } }" class="btn w-full bg-gray-900 text-white transition-colors hover:bg-black hover:shadow-md">Lihat pesanan COD</RouterLink>
            <button v-else-if="order.status === 'menunggu_pembayaran'" class="btn w-full bg-gray-900 text-white transition-colors hover:bg-black hover:shadow-md" type="button" :disabled="checking || isExpired" @click="refreshStatus">
              {{ checking ? 'Memeriksa status…' : isGateway ? 'Coba lagi / perbarui status' : 'Perbarui status pembayaran' }}
            </button>
            <p class="mt-3 text-center text-xs leading-5 text-slate-500">
              {{ isCod ? 'Pembayaran COD dilakukan kepada kurir saat pesanan diterima.' : isGateway ? 'Status Midtrans diperbarui otomatis. Jangan membayar ulang jika transaksi masih diproses.' : 'Setelah transfer, pembayaran akan diteruskan ke admin untuk verifikasi.' }}
            </p>
            <p v-if="!isCod" class="mt-2 text-center text-[11px] leading-5 text-slate-400">Jangan anggap pembayaran berhasil sebelum status terkonfirmasi.</p>
          </div>
        </section>
        <p class="mt-4 text-center text-xs text-slate-400">Simpan nomor pesanan Anda untuk referensi: {{ order.order_no }}</p>
      </template>
    </div>
  </div>
</template>
