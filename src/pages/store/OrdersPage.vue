<script setup>
import { onMounted, ref } from 'vue'
import { RouterLink } from 'vue-router'
import ModalDialog from '@/components/ModalDialog.vue'
import { useAuthStore } from '@/stores/auth'
import { cancelOrder, listMyOrders } from '@/services/orderService'
import { createProductReview, listMyReviewedProductIds } from '@/services/productReviewService'
import { formatRupiah, formatTanggal } from '@/lib/format'
import { ORDER_STATUS } from '@/lib/status'

const auth = useAuthStore()
const orders = ref([])
const reviewedProductIds = ref([])
const loading = ref(true)
const error = ref('')
const notice = ref('')
const reviewOpen = ref(false)
const reviewProduct = ref(null)
const reviewRating = ref(0)
const reviewComment = ref('')
const reviewError = ref('')
const reviewSaving = ref(false)
const cancelTarget = ref(null)
const cancelError = ref('')
const cancelSaving = ref(false)

async function load() {
  loading.value = true
  error.value = ''
  try {
    const [myOrders, reviewedIds] = await Promise.all([
      listMyOrders(auth.user.id),
      listMyReviewedProductIds(),
    ])
    orders.value = myOrders
    reviewedProductIds.value = reviewedIds
  }
  catch (e) { error.value = e.message }
  finally { loading.value = false }
}
onMounted(load)

const ringkas = (o) => o.order_items.map((i) => `${i.product_name} × ${i.quantity}`).join(', ')

function sudahDiulas(productId) {
  return reviewedProductIds.value.includes(productId)
}

function bisaDibatalkan(order) {
  return order.status === 'menunggu_pembayaran'
    || (['menunggu_diproses', 'diproses'].includes(order.status)
      && order.order_items.length > 0
      && order.order_items.every((item) => item.seller_shipping_status === 'menunggu_diproses'))
}

async function batalkanPesanan() {
  if (!cancelTarget.value || !bisaDibatalkan(cancelTarget.value)) return
  cancelSaving.value = true
  cancelError.value = ''
  try {
    await cancelOrder(cancelTarget.value.id)
    notice.value = 'Pesanan dibatalkan.'
    cancelTarget.value = null
    await load()
  } catch (e) {
    cancelError.value = e.message
  } finally {
    cancelSaving.value = false
  }
}

function mulaiUlasan(item) {
  reviewProduct.value = item
  reviewRating.value = 0
  reviewComment.value = ''
  reviewError.value = ''
  reviewOpen.value = true
}

async function kirimUlasan() {
  if (!reviewProduct.value || reviewRating.value < 1 || reviewRating.value > 5) {
    reviewError.value = 'Pilih rating bintang 1 sampai 5.'
    return
  }
  reviewSaving.value = true
  reviewError.value = ''
  try {
    await createProductReview({
      productId: reviewProduct.value.product_id,
      userId: auth.user.id,
      rating: reviewRating.value,
      comment: reviewComment.value,
    })
    reviewedProductIds.value = [...reviewedProductIds.value, reviewProduct.value.product_id]
    reviewOpen.value = false
    notice.value = 'Ulasan berhasil dikirim. Terima kasih!'
  } catch (e) {
    reviewError.value = e.message
  } finally {
    reviewSaving.value = false
  }
}
</script>

<template>
  <div class="mx-auto max-w-4xl px-4 pb-16 pt-8 md:px-6 lg:px-8">
    <h1 class="text-3xl font-bold">Pesanan saya</h1>

    <p v-if="notice" class="mt-4 rounded-xl bg-ok-bg p-3 text-sm text-ok-fg" role="status">{{ notice }}</p>
    <p v-if="error" class="mt-4 rounded-xl bg-bad-bg p-4 text-sm text-bad-fg" role="alert">
      Pesanan belum bisa dimuat: {{ error }}
      <button class="ml-2 font-semibold underline" type="button" @click="load">Coba lagi</button>
    </p>
    <div v-else-if="loading" class="mt-6 h-32 animate-pulse rounded-xl bg-surface"></div>
    <div v-else-if="!orders.length" class="mt-6 rounded-xl bg-surface p-10 text-center">
      <p class="font-semibold">Belum ada pesanan</p>
      <p class="mt-1 text-sm text-muted">Pesanan yang Anda buat akan muncul di sini.</p>
      <RouterLink :to="{ name: 'katalog' }" class="btn bg-gray-900 text-white transition-colors hover:bg-black hover:shadow-md mt-5">Mulai belanja</RouterLink>
    </div>
    <ul v-else class="mt-6 flex flex-col gap-3">
      <li v-for="o in orders" :key="o.id">
        <div class="card p-4">
          <RouterLink :to="{ name: 'pesanan-detail', params: { id: o.id } }" class="flex flex-wrap items-center justify-between gap-3 rounded-lg hover:bg-gray-50">
            <div class="min-w-0">
              <p class="font-semibold">{{ o.order_no }} <span class="ml-1 text-sm font-normal text-muted">{{ formatTanggal(o.created_at) }}</span></p>
              <p class="mt-1 max-w-md truncate text-sm text-muted">{{ ringkas(o) }}</p>
            </div>
            <div class="flex items-center gap-3">
              <span class="badge" :class="ORDER_STATUS[o.status].cls">{{ ORDER_STATUS[o.status].label }}</span>
              <span class="font-bold text-gray-900">{{ formatRupiah(o.total) }}</span>
            </div>
          </RouterLink>
          <div v-if="bisaDibatalkan(o)" class="mt-3 flex justify-end border-t border-line pt-3">
            <button
              class="rounded-lg border border-gray-900 px-3 py-2 text-xs font-semibold text-gray-900 transition hover:bg-gray-50"
              type="button"
              @click="cancelTarget = o; cancelError = ''"
            >Batalkan Pesanan</button>
          </div>
          <div v-if="o.status === 'selesai' && o.order_items.some((item) => item.product_id)" class="mt-3 border-t border-line pt-3">
            <p class="mb-2 text-xs font-medium text-muted">Ulasan produk pesanan ini</p>
            <ul class="space-y-2">
              <li v-for="item in o.order_items.filter((row) => row.product_id)" :key="item.product_id" class="flex flex-wrap items-center justify-between gap-2 text-sm">
                <span class="min-w-0 flex-1 truncate">{{ item.product_name }}</span>
                <span v-if="sudahDiulas(item.product_id)" class="text-xs font-medium text-ok-fg">Sudah diulas</span>
                <button v-else class="rounded-lg border border-gray-900 px-3 py-2 text-xs font-semibold text-gray-900 transition hover:bg-gray-50" type="button" @click="mulaiUlasan(item)">
                  Beri Ulasan
                </button>
              </li>
            </ul>
          </div>
        </div>
      </li>
    </ul>

    <ModalDialog :open="reviewOpen" :title="`Ulasan ${reviewProduct?.product_name || 'Produk'}`" @close="reviewOpen = false">
      <form class="space-y-4" @submit.prevent="kirimUlasan">
        <fieldset>
          <legend class="text-sm font-medium">Rating produk</legend>
          <div class="mt-2 flex items-center gap-1" role="group" aria-label="Pilih rating bintang">
            <button
              v-for="star in 5"
              :key="star"
              class="rounded p-1 text-3xl leading-none transition hover:scale-110 focus-visible:outline-2"
              :class="star <= reviewRating ? 'text-gray-900' : 'text-slate-300'"
              type="button"
              :aria-label="`${star} bintang`"
              :aria-pressed="reviewRating === star"
              @click="reviewRating = star"
            >★</button>
          </div>
        </fieldset>
        <div>
          <label for="review-comment" class="mb-1.5 block text-sm font-medium">Komentar <span class="font-normal text-muted">(opsional)</span></label>
          <textarea id="review-comment" v-model="reviewComment" class="input min-h-28 resize-y py-3" maxlength="2000" placeholder="Bagikan pengalaman Anda menggunakan produk ini"></textarea>
          <p class="mt-1 text-right text-xs text-muted">{{ reviewComment.length }}/2000</p>
        </div>
        <p v-if="reviewError" class="rounded-xl bg-bad-bg p-3 text-sm text-bad-fg" role="alert">{{ reviewError }}</p>
        <div class="flex justify-end gap-2">
          <button class="btn-outline" type="button" :disabled="reviewSaving" @click="reviewOpen = false">Batal</button>
          <button class="btn bg-gray-900 text-white transition-colors hover:bg-black hover:shadow-md" type="submit" :disabled="reviewSaving">{{ reviewSaving ? 'Mengirim…' : 'Kirim ulasan' }}</button>
        </div>
      </form>
    </ModalDialog>

    <ModalDialog :open="!!cancelTarget" title="Batalkan pesanan?" @close="cancelTarget = null">
      <div class="space-y-4">
        <p class="text-sm leading-6 text-muted">
          Apakah Anda yakin ingin membatalkan pesanan <strong class="text-ink">{{ cancelTarget?.order_no }}</strong>?
          Tindakan ini tidak dapat dibatalkan.
        </p>
        <p v-if="cancelError" class="rounded-xl bg-bad-bg p-3 text-sm text-bad-fg" role="alert">{{ cancelError }}</p>
        <div class="flex justify-end gap-2">
          <button class="btn-outline" type="button" :disabled="cancelSaving" @click="cancelTarget = null">Kembali</button>
          <button class="rounded-lg bg-gray-900 px-4 py-2 text-sm font-semibold text-white transition hover:bg-black disabled:opacity-50" type="button" :disabled="cancelSaving" @click="batalkanPesanan">
            {{ cancelSaving ? 'Membatalkan…' : 'Ya, batalkan' }}
          </button>
        </div>
      </div>
    </ModalDialog>
  </div>
</template>
