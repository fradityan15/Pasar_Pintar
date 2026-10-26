<script setup>
import { onMounted, ref } from 'vue'
import { RouterLink } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { listMyOrders } from '@/services/orderService'
import { formatRupiah, formatTanggal } from '@/lib/format'
import { ORDER_STATUS } from '@/lib/status'

const auth = useAuthStore()
const orders = ref([])
const loading = ref(true)
const error = ref('')

async function load() {
  loading.value = true
  error.value = ''
  try { orders.value = await listMyOrders(auth.user.id) }
  catch (e) { error.value = e.message }
  finally { loading.value = false }
}
onMounted(load)

const ringkas = (o) => o.order_items.map((i) => `${i.product_name} × ${i.quantity}`).join(', ')
</script>

<template>
  <div class="mx-auto max-w-4xl px-4 pb-16 pt-8 md:px-6 lg:px-8">
    <h1 class="text-3xl font-bold">Pesanan saya</h1>

    <p v-if="error" class="mt-4 rounded-xl bg-bad-bg p-4 text-sm text-bad-fg" role="alert">
      Pesanan belum bisa dimuat: {{ error }}
      <button class="ml-2 font-semibold underline" type="button" @click="load">Coba lagi</button>
    </p>
    <div v-else-if="loading" class="mt-6 h-32 animate-pulse rounded-xl bg-surface"></div>
    <div v-else-if="!orders.length" class="mt-6 rounded-xl bg-surface p-10 text-center">
      <p class="font-semibold">Belum ada pesanan</p>
      <p class="mt-1 text-sm text-muted">Pesanan yang Anda buat akan muncul di sini.</p>
      <RouterLink :to="{ name: 'katalog' }" class="btn-primary mt-5">Mulai belanja</RouterLink>
    </div>
    <ul v-else class="mt-6 flex flex-col gap-3">
      <li v-for="o in orders" :key="o.id">
        <RouterLink :to="{ name: 'pesanan-detail', params: { id: o.id } }" class="card flex flex-wrap items-center justify-between gap-3 p-4 hover:bg-surface">
          <div class="min-w-0">
            <p class="font-semibold">{{ o.order_no }} <span class="ml-1 text-sm font-normal text-muted">{{ formatTanggal(o.created_at) }}</span></p>
            <p class="mt-1 max-w-md truncate text-sm text-muted">{{ ringkas(o) }}</p>
          </div>
          <div class="flex items-center gap-3">
            <span class="badge" :class="ORDER_STATUS[o.status].cls">{{ ORDER_STATUS[o.status].label }}</span>
            <span class="font-semibold">{{ formatRupiah(o.total) }}</span>
          </div>
        </RouterLink>
      </li>
    </ul>
  </div>
</template>
