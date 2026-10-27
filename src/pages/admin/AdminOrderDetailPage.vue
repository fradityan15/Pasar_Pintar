<script setup>
import { computed, onMounted, ref } from 'vue'
import { RouterLink, useRoute } from 'vue-router'
import OrderTracking from '@/components/OrderTracking.vue'
import ModalDialog from '@/components/ModalDialog.vue'
import StatusBadge from '@/components/StatusBadge.vue'
import { cancelOrderAdmin, confirmOrderPaymentAdmin, getOrderAdmin, setOrderStatus } from '@/services/adminOrderService'
import { formatRupiah } from '@/lib/format'
import { PAYMENT_METHOD } from '@/lib/status'

const route = useRoute()
const order = ref(null)
const loading = ref(true)
const error = ref('')
const info = ref('')
const busy = ref(false)
const note = ref('')
const cancelOpen = ref(false)
const reason = ref('')
const paymentConfirmOpen = ref(false)
const paymentReference = ref('')

const addr = computed(() => order.value?.shipping_address ?? {})
const status = computed(() => order.value?.status)

async function load() {
  loading.value = true
  error.value = ''
  try { order.value = await getOrderAdmin(route.params.id) }
  catch (e) { error.value = e.message }
  finally { loading.value = false }
}
onMounted(load)

async function run(fn, pesan) {
  busy.value = true
  error.value = ''
  info.value = ''
  try {
    await fn()
    info.value = pesan
    note.value = ''
    order.value = await getOrderAdmin(route.params.id)
    return true
  } catch (e) {
    error.value = e.message
    return false
  } finally {
    busy.value = false
  }
}
const kirim = () => run(() => setOrderStatus(order.value.id, 'dikirim', note.value.trim() || null), 'Status diubah menjadi Dikirim.')
const selesai = () => run(() => setOrderStatus(order.value.id, 'selesai', note.value.trim() || null), 'Pesanan ditandai Selesai.')
async function konfirmasiPembayaran() {
  const success = await run(
    () => confirmOrderPaymentAdmin(order.value.id, paymentReference.value.trim() || null),
    'Pembayaran diverifikasi dan pesanan diteruskan ke penjual.',
  )
  if (!success) return
  paymentConfirmOpen.value = false
  paymentReference.value = ''
}
async function batalkan() {
  const success = await run(() => cancelOrderAdmin(order.value.id, reason.value.trim()), 'Pesanan dibatalkan dan stok dikembalikan.')
  if (!success) return
  cancelOpen.value = false
  reason.value = ''
}
</script>

<template>
  <RouterLink :to="{ name: 'admin-pesanan' }" class="text-sm font-medium text-muted">← Semua pesanan</RouterLink>

  <div v-if="loading" class="mt-4 h-48 animate-pulse rounded-xl bg-white"></div>
  <p v-else-if="error && !order" class="mt-4 rounded-xl bg-bad-bg p-4 text-sm text-bad-fg" role="alert">{{ error }}</p>
  <p v-else-if="!order" class="mt-4 rounded-xl bg-white p-8 text-center font-semibold">Pesanan tidak ditemukan</p>

  <template v-else>
    <div class="mt-3 flex flex-wrap items-center gap-3">
      <h1 class="text-2xl font-bold">{{ order.order_no }}</h1>
      <StatusBadge :status="order.status" />
    </div>
    <p v-if="info" class="mt-3 rounded-xl bg-ok-bg p-3 text-sm text-ok-fg" role="status">{{ info }}</p>
    <p v-if="error" class="mt-3 rounded-xl bg-bad-bg p-3 text-sm text-bad-fg" role="alert">{{ error }}</p>

    <section v-if="['menunggu_pembayaran', 'diproses', 'dikirim'].includes(status)" class="card mt-4 flex flex-wrap items-end gap-3 p-5">
      <div v-if="status !== 'menunggu_pembayaran'" class="min-w-[220px] flex-1">
        <label for="catatan" class="mb-1.5 block text-sm font-medium">Catatan (opsional)</label>
        <input id="catatan" v-model="note" class="input" placeholder="Mis. nomor resi" />
      </div>
      <button v-if="status === 'diproses'" class="btn-primary" type="button" :disabled="busy" @click="kirim">Tandai dikirim</button>
      <button v-if="status === 'dikirim'" class="btn-primary" type="button" :disabled="busy" @click="selesai">Tandai selesai</button>
      <button v-if="['menunggu_pembayaran', 'diproses'].includes(status)" class="btn border border-bad-fg text-bad-fg" type="button" :disabled="busy" @click="cancelOpen = true">Batalkan pesanan</button>
      <button
        v-if="status === 'menunggu_pembayaran' && order.payment_status !== 'dibayar' && order.payment_methods?.category !== 'cod' && order.payment_method !== 'cod'"
        class="btn-primary"
        type="button"
        :disabled="busy"
        @click="paymentConfirmOpen = true"
      >Verifikasi pembayaran</button>
    </section>

    <div class="mt-4 grid gap-4 lg:grid-cols-[1fr_340px]">
      <section class="card p-5">
        <h2 class="text-base font-semibold">Barang</h2>
        <ul class="mt-3 flex flex-col gap-2 text-sm">
          <li v-for="i in order.order_items" :key="i.id" class="flex justify-between gap-3">
            <span>{{ i.product_name }} × {{ i.quantity }}</span><span>{{ formatRupiah(i.unit_price * i.quantity) }}</span>
          </li>
        </ul>
        <dl class="mt-3 flex flex-col gap-2 border-t border-line pt-3 text-sm">
          <div class="flex justify-between"><dt class="text-muted">Subtotal</dt><dd>{{ formatRupiah(order.subtotal) }}</dd></div>
          <div class="flex justify-between"><dt class="text-muted">Ongkir</dt><dd>{{ formatRupiah(order.shipping_cost) }}</dd></div>
          <div class="flex justify-between text-base font-bold"><dt>Total</dt><dd>{{ formatRupiah(order.total) }}</dd></div>
        </dl>
        <p class="mt-3 text-xs text-muted">Pembayaran: {{ order.payment_methods?.name || PAYMENT_METHOD[order.payment_method] || order.payment_method }} · {{ order.payment_status.replace('_', ' ') }}</p>
      </section>

      <div class="flex flex-col gap-4">
        <section class="card p-5 text-sm">
          <h2 class="text-base font-semibold">Pelanggan</h2>
          <p class="mt-2 font-medium">{{ order.profiles?.full_name || '-' }}</p>
          <p class="text-muted">{{ order.profiles?.phone || 'Telepon belum diisi' }}</p>
          <h2 class="mt-4 text-base font-semibold">Alamat pengiriman</h2>
          <p class="mt-2"><b>{{ addr.recipient_name }}</b> ({{ addr.phone }})</p>
          <p class="text-muted">{{ addr.street }}, {{ addr.city }}, {{ addr.province }} {{ addr.postal_code }}</p>
        </section>
        <OrderTracking :order-id="order.id" user-role="admin" />
      </div>
    </div>

    <ModalDialog :open="cancelOpen" title="Batalkan pesanan" @close="cancelOpen = false">
      <form class="flex flex-col gap-3" @submit.prevent="batalkan">
        <p class="text-sm text-muted">Stok barang akan dikembalikan. Alasan akan tercatat di riwayat.</p>
        <div>
          <label for="alasan" class="mb-1.5 block text-sm font-medium">Alasan pembatalan</label>
          <textarea id="alasan" v-model="reason" class="input py-2" rows="3" minlength="5" required></textarea>
        </div>
        <div class="flex justify-end gap-2">
          <button class="btn-outline" type="button" @click="cancelOpen = false">Kembali</button>
          <button class="btn bg-bad-fg text-white" type="submit" :disabled="busy">Batalkan pesanan</button>
        </div>
      </form>
    </ModalDialog>

    <ModalDialog :open="paymentConfirmOpen" title="Verifikasi pembayaran" @close="paymentConfirmOpen = false">
      <form class="flex flex-col gap-3" @submit.prevent="konfirmasiPembayaran">
        <p class="text-sm leading-6 text-muted">
          Pastikan dana transfer sudah benar-benar masuk sebelum mengonfirmasi. Setelah diverifikasi, pesanan dapat diproses penjual.
        </p>
        <div>
          <label for="payment-reference" class="mb-1.5 block text-sm font-medium">Referensi transfer <span class="font-normal text-muted">(opsional)</span></label>
          <input id="payment-reference" v-model="paymentReference" class="input" maxlength="200" />
        </div>
        <div class="flex justify-end gap-2">
          <button class="btn-outline" type="button" :disabled="busy" @click="paymentConfirmOpen = false">Kembali</button>
          <button class="btn-primary" type="submit" :disabled="busy">{{ busy ? 'Memverifikasi…' : 'Konfirmasi dana diterima' }}</button>
        </div>
      </form>
    </ModalDialog>
  </template>
</template>
