<script setup>
import { onMounted, ref, watch } from 'vue'
import { supabase } from '@/lib/supabase'
import { formatTanggalJam } from '@/lib/format'
import { ORDER_STATUS } from '@/lib/status'

const props = defineProps({
  orderId: { type: String, required: true },
  userRole: { type: String, required: true, validator: (role) => ['buyer', 'seller', 'admin'].includes(role) },
  compact: { type: Boolean, default: false },
})

const logs = ref([])
const shipments = ref([])
const shipmentEvents = ref([])
const loading = ref(true)
const error = ref('')
const shippingError = ref('')
let requestId = 0

async function load() {
  const currentRequest = ++requestId
  loading.value = true
  error.value = ''
  shippingError.value = ''
  logs.value = []
  shipments.value = []
  shipmentEvents.value = []
  try {
    let result
    if (props.userRole === 'seller') {
      result = await supabase.rpc('seller_order_status_logs', { p_order_id: props.orderId })
    } else {
      result = await supabase
        .from('order_status_logs')
        .select('id, order_id, status, changed_by, note, created_at')
        .eq('order_id', props.orderId)
        .order('created_at', { ascending: false })
        .order('id', { ascending: false })
    }
    if (result.error) throw new Error(result.error.message)
    if (currentRequest === requestId) logs.value = result.data ?? []
  } catch (e) {
    if (currentRequest === requestId) error.value = e.message
  }
  try {
    const [trackingResult, shipmentResult] = await Promise.all([
      supabase.functions.invoke('shipping-track', { body: { order_id: props.orderId } }),
      supabase.from('order_items')
        .select('courier, courier_service, tracking_number')
        .eq('order_id', props.orderId),
    ])
    if (trackingResult.error) throw new Error(trackingResult.error.message)
    if (shipmentResult.error) throw new Error(shipmentResult.error.message)
    if (currentRequest === requestId) {
      const uniqueShipments = new Map()
      for (const shipment of shipmentResult.data ?? []) {
        if (shipment.courier && shipment.tracking_number) {
          uniqueShipments.set(`${shipment.courier}:${shipment.tracking_number}`, shipment)
        }
      }
      shipments.value = [...uniqueShipments.values()]
      shipmentEvents.value = trackingResult.data?.events ?? []
      shippingError.value = uniqueShipments.size ? trackingResult.data?.warning ?? '' : ''
    }
  } catch (e) {
    if (currentRequest === requestId) shippingError.value = e.message
  } finally {
    if (currentRequest === requestId) loading.value = false
  }
}

onMounted(load)
watch(() => [props.orderId, props.userRole], load)

function statusLabel(status) {
  return ORDER_STATUS[status]?.label ?? status
}

function statusColor(status) {
  if (status === 'selesai') {
    return props.userRole === 'buyer' ? 'bg-indigo-600 ring-indigo-100' : 'bg-emerald-600 ring-emerald-100'
  }
  if (status === 'dibatalkan') return 'bg-red-600 ring-red-100'
  if (status === 'menunggu_pembayaran') return 'bg-amber-500 ring-amber-100'
  if (status === 'menunggu_diproses') return 'bg-sky-500 ring-sky-100'
  return 'bg-teal-600 ring-teal-100'
}
</script>

<template>
  <section class="rounded-xl bg-white shadow-sm ring-1 ring-slate-200" :class="compact ? 'p-4' : 'p-5 sm:p-6'" aria-labelledby="order-tracking-title">
    <div class="flex items-start justify-between gap-3">
      <div class="flex items-center gap-2.5">
        <span
          class="flex h-9 w-9 shrink-0 items-center justify-center rounded-full"
          :class="userRole === 'buyer' ? 'bg-indigo-50 text-indigo-700' : 'bg-emerald-50 text-emerald-700'"
          aria-hidden="true"
        >
          <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="1.8">
            <circle cx="12" cy="12" r="9" /><path stroke-linecap="round" stroke-linejoin="round" d="M12 7v5l3 2" />
          </svg>
        </span>
        <div>
        <h2 id="order-tracking-title" class="text-base font-semibold text-slate-900">Pelacakan Pesanan</h2>
        <p class="mt-1 text-sm text-slate-500">Riwayat perubahan status pesanan.</p>
        </div>
      </div>
      <button
        class="text-sm font-semibold hover:underline disabled:opacity-50"
        :class="userRole === 'buyer' ? 'text-gray-900' : 'text-gray-900'"
        type="button"
        :disabled="loading"
        @click="load"
      >Muat ulang</button>
    </div>

    <div v-if="loading" class="mt-5 space-y-4" aria-live="polite">
      <div v-for="n in 3" :key="n" class="h-14 animate-pulse rounded-lg bg-slate-100"></div>
    </div>
    <div v-else-if="error" class="mt-5 rounded-lg border border-red-100 bg-red-50 p-3 text-sm text-red-700" role="alert">
      {{ error }}
      <button class="ml-1 font-semibold underline" type="button" @click="load">Coba lagi</button>
    </div>
    <p v-else-if="!logs.length" class="mt-5 rounded-lg bg-slate-50 p-4 text-sm text-slate-500">
      Belum ada riwayat status untuk pesanan ini.
    </p>

    <ol v-else :class="compact ? 'mt-4' : 'mt-6'">
      <li v-for="(log, index) in logs" :key="log.id" class="relative flex gap-3 last:pb-0" :class="compact ? 'pb-4' : 'pb-6'">
        <div class="relative flex w-4 shrink-0 justify-center">
          <span v-if="index < logs.length - 1" class="absolute bottom-0 top-3.5 w-px bg-slate-200" aria-hidden="true"></span>
          <span class="relative z-10 mt-1 h-2.5 w-2.5 rounded-full ring-[3px]" :class="statusColor(log.status)" aria-hidden="true"></span>
        </div>
        <div class="min-w-0 flex-1">
          <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
            <p class="font-semibold text-slate-900">{{ statusLabel(log.status) }}</p>
            <time class="text-xs text-slate-500">{{ formatTanggalJam(log.created_at) }}</time>
          </div>
          <p v-if="userRole === 'buyer' && log.note" class="mt-1 text-sm text-slate-600">{{ log.note }}</p>
          <div v-if="userRole === 'admin' || userRole === 'seller'" class="mt-2 space-y-0.5 text-xs text-gray-500">
            <p>ID Log: {{ log.id }}</p>
            <p>Diubah oleh: {{ log.changed_by || 'Sistem' }}</p>
            <p v-if="log.note">Catatan: {{ log.note }}</p>
          </div>
        </div>
      </li>
    </ol>
    <div v-if="!loading && (shipments.length || shippingError)" class="mt-6 border-t border-slate-100 pt-5">
      <h3 class="font-semibold text-slate-900">Pengiriman & pelacakan kurir</h3>
      <p v-if="shippingError" class="mt-3 rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900" role="status">
        {{ shippingError }}
      </p>
      <div v-for="shipment in shipments" :key="`${shipment.courier}:${shipment.tracking_number}`" class="mt-3 rounded-lg border border-slate-200 p-3">
        <p class="text-sm font-semibold text-slate-900">{{ shipment.courier.toUpperCase() }} · {{ shipment.courier_service || 'Layanan kurir' }}</p>
        <p class="mt-1 text-sm text-slate-600">Nomor resi: <span class="font-mono font-medium text-slate-900">{{ shipment.tracking_number }}</span></p>
        <p v-if="shipment.tracking_number.startsWith('DEMO-')" class="mt-2 rounded-md bg-amber-50 p-2 text-xs text-amber-800">
          Resi demo untuk presentasi. Nomor dan status ini tidak terhubung ke pelacakan kurir sungguhan.
        </p>
      </div>
      <ol v-if="shipmentEvents.length" class="mt-4 border-l border-slate-200 pl-4">
        <li v-for="event in shipmentEvents" :key="event.id" class="relative pb-4 last:pb-0">
          <span class="absolute -left-[21px] top-1 h-2.5 w-2.5 rounded-full bg-indigo-600 ring-4 ring-indigo-50" aria-hidden="true"></span>
          <div class="flex flex-wrap justify-between gap-2">
            <p class="text-sm font-semibold text-slate-900">{{ event.status }}</p>
            <time class="text-xs text-slate-500">{{ formatTanggalJam(event.occurred_at) }}</time>
          </div>
          <p v-if="event.description" class="mt-1 text-sm text-slate-600">{{ event.description }}</p>
          <p class="mt-1 text-xs text-slate-500">{{ event.courier.toUpperCase() }} · {{ event.tracking_number }}</p>
        </li>
      </ol>
      <p v-else-if="shipments.length && !shippingError" class="mt-3 text-sm text-slate-500">
        Belum ada peristiwa pelacakan dari kurir. Muat ulang kembali nanti.
      </p>
    </div>
  </section>
</template>
