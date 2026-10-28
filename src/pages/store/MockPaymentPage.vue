<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { RouterLink, useRoute, useRouter } from 'vue-router'
import { getOrder } from '@/services/orderService'
import { useAuthStore } from '@/stores/auth'
import { formatRupiah, formatTanggalJam } from '@/lib/format'

const route = useRoute()
const router = useRouter()
const auth = useAuthStore()
const order = ref(null)
const loading = ref(true)
const error = ref('')
const confirming = ref(false)
const now = ref(Date.now())
let countdownTimer

const paymentMethod = computed(() => order.value?.payment_methods)
const isCod = computed(() => order.value?.payment_method === 'cod' || paymentMethod.value?.category === 'cod')
const isWaitingForCod = computed(() => isCod.value && !isPaid.value && order.value?.status !== 'dibatalkan')
const isPaid = computed(() => order.value?.payment_status === 'dibayar')
const expiryTime = computed(() => order.value?.payment_expires_at ? new Date(order.value.payment_expires_at).getTime() : null)
const remainingSeconds = computed(() => expiryTime.value ? Math.max(0, Math.floor((expiryTime.value - now.value) / 1000)) : 0)
const isExpired = computed(() => !isCod.value && expiryTime.value !== null && remainingSeconds.value === 0)
const countdown = computed(() => {
  const hours = Math.floor(remainingSeconds.value / 3600)
  const minutes = Math.floor((remainingSeconds.value % 3600) / 60)
  const seconds = remainingSeconds.value % 60
  return [hours, minutes, seconds].map((part) => String(part).padStart(2, '0')).join(':')
})

async function load() {
  loading.value = true
  error.value = ''
  try {
    order.value = await getOrder(route.params.orderId, auth.user.id)
    if (!order.value) error.value = 'Pesanan tidak ditemukan atau tidak dapat diakses.'
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

async function perbaruiStatusPembayaran() {
  confirming.value = true
  error.value = ''
  try {
    const latestOrder = await getOrder(route.params.orderId, auth.user.id)
    if (!latestOrder) throw new Error('Pesanan tidak ditemukan atau tidak dapat diakses.')
    order.value = latestOrder
    if (latestOrder.payment_status === 'dibayar') {
      await router.replace({ name: 'pesanan-detail', params: { id: latestOrder.id } })
    }
  } catch (e) {
    error.value = e.message
  } finally {
    confirming.value = false
  }
}

onMounted(() => {
  load()
  countdownTimer = window.setInterval(() => { now.value = Date.now() }, 1000)
})

onBeforeUnmount(() => window.clearInterval(countdownTimer))
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
          <div class="flex items-start gap-4">
            <span class="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-indigo-50 text-indigo-700">
              <svg viewBox="0 0 24 24" class="h-6 w-6" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
                <rect x="3" y="5" width="18" height="14" rx="2" />
                <path stroke-linecap="round" stroke-linejoin="round" d="M3 10h18M7 15h3" />
              </svg>
            </span>
            <div class="min-w-0 flex-1">
              <p class="text-sm font-medium text-indigo-700">{{ isPaid ? 'Pembayaran terkonfirmasi' : isCod ? 'Pesanan berhasil dibuat' : 'Selesaikan pembayaran Anda' }}</p>
              <h1 class="mt-1 text-2xl font-bold tracking-tight text-slate-900 sm:text-3xl">
                {{ isPaid ? 'Pembayaran Berhasil' : isCod ? 'Instruksi Pembayaran COD' : 'Menunggu Pembayaran' }}
              </h1>
              <p class="mt-2 text-sm text-slate-500">Pesanan {{ order.order_no }}</p>
            </div>
          </div>

          <div class="mt-6 flex flex-wrap items-end justify-between gap-4 border-t border-slate-100 pt-5">
            <div>
              <p class="text-sm text-slate-500">{{ isCod ? 'Total yang dibayarkan kepada kurir' : 'Total tagihan' }}</p>
              <p class="mt-1 text-3xl font-bold tracking-tight text-gray-900">{{ formatRupiah(order.total) }}</p>
            </div>
            <div v-if="!isCod && !isPaid" class="rounded-xl bg-amber-50 px-4 py-3 text-right">
              <p class="text-xs font-medium text-amber-800">Bayar sebelum</p>
              <time v-if="order.payment_expires_at" class="mt-1 block text-sm font-semibold text-amber-950" :datetime="order.payment_expires_at">
                {{ formatTanggalJam(order.payment_expires_at) }}
              </time>
              <p v-else class="mt-1 text-sm font-semibold text-amber-950" aria-live="off">{{ countdown }}</p>
              <p v-if="order.payment_expires_at" class="mt-1 font-mono text-lg font-bold tabular-nums text-amber-950" role="timer" aria-label="Sisa waktu pembayaran">
                {{ countdown }}
              </p>
            </div>
          </div>
        </header>

        <section class="mt-5 rounded-2xl bg-white p-5 shadow-sm ring-1 ring-slate-200 sm:p-7">
          <div class="flex items-center gap-3 border-b border-slate-100 pb-4">
            <span class="flex h-9 w-9 items-center justify-center rounded-full bg-slate-100 text-slate-700" aria-hidden="true">
              <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                <path d="m3 9 9-5 9 5M5 10v8m4-8v8m6-8v8m4-8v8M3 20h18M2 10h20" />
              </svg>
            </span>
            <div>
              <h2 class="font-semibold text-slate-900">{{ paymentMethod?.name || 'Metode pembayaran' }}</h2>
              <p class="mt-0.5 text-xs text-slate-500">Instruksi pembayaran</p>
            </div>
          </div>

          <div v-if="isPaid" class="mt-5 rounded-xl border border-indigo-100 bg-indigo-50 p-4 text-sm leading-6 text-indigo-900" role="status">
            Pembayaran pesanan ini sudah dikonfirmasi. Pesanan sedang diteruskan untuk diproses.
          </div>
          <div v-else-if="isExpired" class="mt-5 rounded-xl border border-red-100 bg-red-50 p-4 text-sm leading-6 text-red-800" role="alert">
            Batas waktu pembayaran telah berakhir. Silakan lihat status pesanan atau hubungi pengelola toko untuk bantuan.
          </div>
          <div v-else-if="isCod" class="mt-5 rounded-xl border border-slate-200 bg-slate-50 p-5">
            <p class="font-semibold text-slate-900">Bayar saat pesanan diterima</p>
            <p class="mt-2 text-sm leading-6 text-slate-600">
              Siapkan pembayaran sebesar <span class="font-bold text-gray-900">{{ formatRupiah(order.total) }}</span> untuk kurir saat barang tiba.
            </p>
          </div>
          <div v-else-if="paymentMethod?.category === 'qris'" class="mt-5 flex flex-col items-center rounded-xl border border-slate-200 bg-slate-50 p-5 text-center">
            <p class="text-sm leading-6 text-slate-600">Pindai kode QR berikut melalui aplikasi mobile banking atau dompet digital Anda.</p>
            <img
              v-if="paymentMethod.qr_image_url"
              :src="paymentMethod.qr_image_url"
              :alt="`Kode QR pembayaran ${paymentMethod.name}`"
              class="mt-5 max-h-80 max-w-full rounded-xl bg-white p-2 object-contain shadow-sm ring-1 ring-slate-200"
            />
            <p v-else class="mt-4 text-sm text-red-700" role="alert">Kode QR belum tersedia. Silakan hubungi pengelola toko.</p>
            <p class="mt-4 text-xs text-slate-500">Pastikan nominal pembayaran sesuai dengan total tagihan.</p>
          </div>
          <div v-else-if="['va', 'bank_transfer'].includes(paymentMethod?.category)" class="mt-5 rounded-xl border border-slate-200 bg-slate-50 p-5">
            <p class="text-sm leading-6 text-slate-600">Silakan transfer tepat sesuai total tagihan ke rekening berikut.</p>
            <dl class="mt-4 divide-y divide-slate-200 rounded-xl border border-slate-200 bg-white px-4">
              <div class="flex flex-wrap justify-between gap-2 py-3 text-sm">
                <dt class="text-slate-500">Bank</dt>
                <dd class="font-semibold text-slate-900">{{ paymentMethod.name }}</dd>
              </div>
              <div class="flex flex-wrap justify-between gap-2 py-3 text-sm">
                <dt class="text-slate-500">Nomor rekening</dt>
                <dd class="font-mono font-semibold tracking-wide text-slate-900">{{ paymentMethod.account_number || 'Belum tersedia' }}</dd>
              </div>
              <div class="flex flex-wrap justify-between gap-2 py-3 text-sm">
                <dt class="text-slate-500">Atas nama</dt>
                <dd class="font-semibold text-slate-900">{{ paymentMethod.account_name || 'Belum tersedia' }}</dd>
              </div>
            </dl>
            <p class="mt-3 text-xs leading-5 text-slate-500">Periksa kembali nama penerima sebelum melakukan transfer.</p>
          </div>
          <p v-else-if="!isPaid && !isExpired" class="mt-5 rounded-xl bg-amber-50 p-4 text-sm text-amber-900" role="alert">
            Rincian metode pembayaran belum tersedia. Hubungi pengelola toko sebelum melanjutkan.
          </p>

          <p v-if="error && order" class="mt-4 rounded-xl bg-red-50 p-3 text-sm text-red-700" role="alert">{{ error }}</p>

          <div class="mt-6 border-t border-slate-100 pt-5">
            <RouterLink v-if="isPaid || isExpired" :to="{ name: 'pesanan-detail', params: { id: order.id } }" class="btn bg-gray-900 text-white transition-colors hover:bg-black hover:shadow-md w-full">
              Lihat detail pesanan
            </RouterLink>
            <RouterLink
              v-else-if="isWaitingForCod"
              :to="{ name: 'pesanan-detail', params: { id: order.id } }"
              class="btn bg-gray-900 text-white transition-colors hover:bg-black hover:shadow-md w-full"
            >Lihat pesanan COD</RouterLink>
            <button
              v-else-if="order.status === 'menunggu_pembayaran'"
              class="btn bg-gray-900 text-white transition-colors hover:bg-black hover:shadow-md w-full"
              type="button"
              :disabled="confirming || isExpired"
              @click="perbaruiStatusPembayaran"
            >
              <svg v-if="confirming" class="mr-2 h-4 w-4 animate-spin" viewBox="0 0 24 24" fill="none" aria-hidden="true">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 0 1 8-8V0C5.373 0 0 5.373 0 12h4Z" />
              </svg>
              {{ confirming ? 'Memeriksa status…' : 'Perbarui status pembayaran' }}
            </button>
            <p class="mt-3 text-center text-xs leading-5 text-slate-500">
              {{ isCod ? 'Pembayaran COD dilakukan kepada kurir saat pesanan diterima.' : 'Setelah transfer, pembayaran akan diteruskan ke admin untuk verifikasi. Gunakan tombol di atas untuk memuat status terbaru.' }}
            </p>
            <p v-if="!isCod" class="mt-2 text-center text-[11px] leading-5 text-slate-400">Jangan anggap pembayaran berhasil sebelum status terkonfirmasi.</p>
          </div>
        </section>

        <p class="mt-4 text-center text-xs text-slate-400">Simpan nomor pesanan Anda untuk referensi: {{ order.order_no }}</p>
      </template>
    </div>
  </div>
</template>
