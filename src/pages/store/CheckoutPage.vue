<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
import { RouterLink, useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useCartStore } from '@/stores/cart'
import { createOrder, listActivePaymentMethods, listAddresses, saveAddress } from '@/services/orderService'
import { formatRupiah } from '@/lib/format'
import { FLAT_SHIPPING } from '@/lib/status'

const auth = useAuthStore()
const cart = useCartStore()
const route = useRoute()
const router = useRouter()

const addresses = ref([])
const selected = ref(null)
const paymentMethods = ref([])
const selectedPaymentMethodId = ref(null)
const shippingMethod = ref('regular')
const loading = ref(true)
const showForm = ref(false)
const showAddressPicker = ref(false)
const savingAddr = ref(false)
const placing = ref(false)
const error = ref('')

const blank = () => ({
  label: 'Rumah',
  recipient_name: auth.profile?.full_name ?? '',
  phone: auth.profile?.phone ?? '',
  province: '',
  city: '',
  street: '',
  postal_code: '',
})
const form = reactive(blank())

function sanitizeNumeric(field, event) {
  const value = event.target.value.replace(/\D/g, '')
  event.target.value = value
  form[field] = value
}

function sanitizeText(field, event) {
  const value = event.target.value.replace(/[^a-zA-Z\s]/g, '')
  event.target.value = value
  form[field] = value
}

const selectedProductIds = computed(() => {
  const raw = route.query.produk
  if (raw === undefined) return cart.items.map((item) => item.product_id)
  const requested = new Set((Array.isArray(raw) ? raw : String(raw).split(',')).filter(Boolean))
  return cart.items.filter((item) => requested.has(item.product_id)).map((item) => item.product_id)
})
const checkoutItems = computed(() => {
  const ids = new Set(selectedProductIds.value)
  return cart.items.filter((item) => ids.has(item.product_id))
})
const checkoutSubtotal = computed(() => checkoutItems.value.reduce((sum, item) => sum + item.products.price * item.quantity, 0))
const checkoutProblems = computed(() => checkoutItems.value.filter((item) => !item.products.is_active || item.products.stock < item.quantity))
const selectedAddress = computed(() => addresses.value.find((address) => address.id === selected.value) ?? null)
const selectedPaymentMethod = computed(() =>
  paymentMethods.value.find((paymentMethod) => paymentMethod.id === selectedPaymentMethodId.value) ?? null,
)

const shippingOptions = computed(() => [
  { id: 'regular', name: 'Pengiriman standar', detail: 'Tarif tetap PasarPintar', price: FLAT_SHIPPING },
])
const selectedShipping = computed(() => shippingOptions.value.find((option) => option.id === shippingMethod.value))
const shippingCost = computed(() => checkoutItems.value.length ? (selectedShipping.value?.price ?? 0) : 0)
const total = computed(() => checkoutSubtotal.value + shippingCost.value)

onMounted(async () => {
  try {
    await cart.load()
    addresses.value = await listAddresses()
    paymentMethods.value = await listActivePaymentMethods()
    selected.value = addresses.value.find((address) => address.is_default)?.id ?? addresses.value[0]?.id ?? null
    showForm.value = addresses.value.length === 0
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
})

function imageOf(product) {
  return [...(product.product_images ?? [])].sort((a, b) => a.sort_order - b.sort_order)[0]?.url ?? ''
}

function mulaiTambahAlamat() {
  Object.assign(form, blank())
  showForm.value = true
}

async function simpanAlamat() {
  savingAddr.value = true
  error.value = ''
  try {
    const address = await saveAddress(auth.user.id, { ...form }, addresses.value.length === 0)
    addresses.value.push(address)
    selected.value = address.id
    showForm.value = false
    showAddressPicker.value = false
    Object.assign(form, blank())
  } catch (e) {
    error.value = e.message
  } finally {
    savingAddr.value = false
  }
}

async function buatPesanan() {
  placing.value = true
  error.value = ''
  try {
    const paymentMethodId = selectedPaymentMethod.value?.id
    if (!paymentMethodId) throw new Error('Pilih metode pembayaran terlebih dahulu')
    const orderId = await createOrder(selected.value, paymentMethodId, selectedProductIds.value, shippingMethod.value)
    const selectedIds = new Set(selectedProductIds.value)
    cart.items = cart.items.filter((item) => !selectedIds.has(item.product_id))
    await router.push({ name: 'payment-simulation', params: { orderId } })
  } catch (e) {
    error.value = e.message
    await cart.load()
  } finally {
    placing.value = false
  }
}
</script>

<template>
  <div class="mx-auto max-w-7xl px-4 pb-16 pt-8 md:px-6 lg:px-8">
    <RouterLink :to="{ name: 'keranjang' }" class="inline-flex items-center gap-2 text-sm font-medium text-slate-500 transition hover:text-emerald-700">
      <span aria-hidden="true">←</span> Kembali ke keranjang
    </RouterLink>
    <div class="mt-3">
      <p class="text-sm font-medium text-emerald-700">Satu langkah lagi menuju pesanan Anda</p>
      <h1 class="mt-1 text-3xl font-bold text-slate-900">Checkout</h1>
    </div>

    <div v-if="loading" class="mt-6 grid gap-6 lg:grid-cols-[minmax(0,1fr)_360px]">
      <div class="h-[480px] animate-pulse rounded-2xl bg-surface"></div>
      <div class="h-72 animate-pulse rounded-2xl bg-surface"></div>
    </div>

    <div v-else-if="!checkoutItems.length" class="mt-6 rounded-2xl border border-slate-200 bg-white p-10 text-center shadow-sm">
      <p class="font-semibold text-slate-900">Tidak ada barang terpilih untuk di-checkout</p>
      <RouterLink :to="{ name: 'keranjang' }" class="btn-primary mt-5 inline-flex rounded-xl px-6 py-3">Kembali ke keranjang</RouterLink>
    </div>

    <div v-else class="mt-6 grid items-start gap-6 lg:grid-cols-[minmax(0,1fr)_360px] lg:gap-8">
      <div class="flex min-w-0 flex-col gap-5">
        <section class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm sm:p-6">
          <div class="flex items-start gap-3">
            <span class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-emerald-50 text-emerald-700" aria-hidden="true">
              <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="1.8"><path stroke-linecap="round" stroke-linejoin="round" d="M20 10c0 5-8 11-8 11S4 15 4 10a8 8 0 1 1 16 0Z" /><circle cx="12" cy="10" r="2.5" /></svg>
            </span>
            <div class="min-w-0 flex-1">
              <h2 class="text-base font-bold text-slate-900">Alamat Pengiriman</h2>
              <template v-if="selectedAddress">
                <p class="mt-3 text-sm font-semibold text-slate-900">{{ selectedAddress.label }} <span class="font-normal text-slate-500">· {{ selectedAddress.recipient_name }}</span></p>
                <p class="mt-1 text-sm text-slate-600">{{ selectedAddress.phone }}</p>
                <p class="mt-1 text-sm leading-6 text-slate-600">{{ selectedAddress.street }}, {{ selectedAddress.city }}, {{ selectedAddress.province }} {{ selectedAddress.postal_code }}</p>
              </template>
              <p v-else class="mt-3 text-sm text-slate-500">Tambahkan alamat untuk melanjutkan checkout.</p>
              <button
                v-if="addresses.length"
                class="mt-4 inline-flex min-h-10 items-center justify-center rounded-lg border border-emerald-200 px-4 text-sm font-semibold text-emerald-800 transition hover:bg-emerald-50"
                type="button"
                @click="showAddressPicker = true; showForm = false"
              >Ubah / Pilih Alamat Lain</button>
            </div>
          </div>

          <form v-if="showForm && !addresses.length" class="mt-5 grid gap-3 border-t border-slate-100 pt-5 sm:grid-cols-2" @submit.prevent="simpanAlamat">
            <h3 class="text-sm font-semibold text-slate-900 sm:col-span-2">{{ addresses.length ? 'Tambah alamat baru' : 'Alamat pengiriman baru' }}</h3>
            <p v-if="error" class="rounded-lg bg-bad-bg p-3 text-sm text-bad-fg sm:col-span-2" role="alert">{{ error }}</p>
            <div><label for="a-label" class="mb-1 block text-sm font-medium text-slate-700">Label</label><input id="a-label" v-model="form.label" class="input" required /></div>
            <div><label for="a-nama" class="mb-1 block text-sm font-medium text-slate-700">Nama penerima</label><input id="a-nama" v-model="form.recipient_name" class="input" autocomplete="name" required /></div>
            <div><label for="a-hp" class="mb-1 block text-sm font-medium text-slate-700">Nomor telepon</label><input id="a-hp" :value="form.phone" class="input" type="tel" autocomplete="tel" required @input="sanitizeNumeric('phone', $event)" /></div>
            <div><label for="a-prov" class="mb-1 block text-sm font-medium text-slate-700">Provinsi</label><input id="a-prov" :value="form.province" class="input" required @input="sanitizeText('province', $event)" /></div>
            <div><label for="a-kota" class="mb-1 block text-sm font-medium text-slate-700">Kota/Kabupaten</label><input id="a-kota" :value="form.city" class="input" required @input="sanitizeText('city', $event)" /></div>
            <div><label for="a-pos" class="mb-1 block text-sm font-medium text-slate-700">Kode pos</label><input id="a-pos" v-model="form.postal_code" class="input" inputmode="numeric" /></div>
            <div class="sm:col-span-2"><label for="a-jalan" class="mb-1 block text-sm font-medium text-slate-700">Alamat lengkap</label><input id="a-jalan" v-model="form.street" class="input" autocomplete="street-address" required /></div>
            <div class="flex gap-2 sm:col-span-2">
              <button class="btn-primary rounded-lg px-4 py-2.5" type="submit" :disabled="savingAddr">{{ savingAddr ? 'Menyimpan…' : 'Simpan dan gunakan alamat' }}</button>
              <button v-if="addresses.length" class="btn-outline" type="button" @click="showForm = false">Batal</button>
            </div>
          </form>
        </section>

        <section class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm sm:p-6">
          <div>
            <h2 class="text-base font-bold text-slate-900">Pilih Pengiriman</h2>
            <p class="mt-1 text-sm text-slate-500">Pilih layanan pengiriman untuk pesanan Anda.</p>
          </div>
          <fieldset class="mt-4 grid gap-3 sm:grid-cols-2">
            <legend class="sr-only">Pilihan pengiriman</legend>
            <label
              v-for="option in shippingOptions"
              :key="option.id"
              class="flex cursor-pointer items-start gap-3 rounded-xl border p-4 transition"
              :class="shippingMethod === option.id ? 'border-emerald-600 bg-emerald-50/60 ring-1 ring-emerald-600' : 'border-slate-200 hover:border-slate-300'"
            >
              <input v-model="shippingMethod" type="radio" name="pengiriman" :value="option.id" class="mt-1 h-4 w-4 border-slate-300 text-emerald-700 focus:ring-emerald-600" />
              <span class="min-w-0 flex-1">
                <span class="flex items-center justify-between gap-2">
                  <span class="text-sm font-semibold text-slate-900">{{ option.name }}</span>
                  <span class="text-sm font-semibold text-slate-900">{{ formatRupiah(option.price) }}</span>
                </span>
                <span class="mt-1 block text-xs text-slate-500">{{ option.detail }}</span>
                <span class="mt-2 block text-xs font-medium text-emerald-800">Layanan pengiriman standar</span>
              </span>
            </label>
          </fieldset>
          <p class="mt-3 text-xs leading-5 text-slate-500">Tarif pengiriman standar mengikuti tarif tetap PasarPintar.</p>
        </section>

        <section class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm sm:p-6">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h2 class="text-base font-bold text-slate-900">Metode Pembayaran</h2>
          </div>
          <fieldset class="mt-4 space-y-3">
            <legend class="sr-only">Pilih metode pembayaran</legend>
            <template v-for="paymentMethod in paymentMethods" :key="paymentMethod.id">
              <label
                class="flex cursor-pointer items-center gap-4 rounded-xl border p-4 transition-colors hover:bg-slate-50"
                :class="selectedPaymentMethodId === paymentMethod.id ? 'border-emerald-600 bg-emerald-50 ring-1 ring-emerald-600' : 'border-slate-200'"
              >
                <input v-model="selectedPaymentMethodId" type="radio" name="metode" :value="paymentMethod.id" class="h-4 w-4 border-slate-300 text-emerald-700 focus:ring-emerald-600" />
                <span class="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-white text-slate-600 ring-1 ring-slate-200" aria-hidden="true">
                  <svg v-if="paymentMethod.category === 'qris'" viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="1.7">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h2v2h-2zm4 0h2v6h-2zm-4 4h2v2h-2z" />
                  </svg>
                  <svg v-else-if="['va', 'bank_transfer'].includes(paymentMethod.category)" viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="1.7">
                    <path stroke-linecap="round" stroke-linejoin="round" d="m3 9 9-5 9 5M5 10v8m4-8v8m6-8v8m4-8v8M3 20h18M2 10h20" />
                  </svg>
                  <svg v-else-if="paymentMethod.category === 'cod'" viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="1.7">
                    <rect x="3" y="6" width="18" height="12" rx="2" />
                    <circle cx="12" cy="12" r="2.5" />
                    <path stroke-linecap="round" d="M6 9h.01M18 15h.01" />
                  </svg>
                  <svg v-else viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="1.7">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M12 3v18m5-14H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6" />
                  </svg>
                </span>
                <span class="min-w-0 flex-1">
                  <span class="block text-sm font-semibold text-slate-900">{{ paymentMethod.name }}</span>
                </span>
              </label>

              <div v-if="selectedPaymentMethodId === paymentMethod.id" class="rounded-xl border border-emerald-100 bg-emerald-50/50 p-4">
                <div v-if="paymentMethod.category === 'qris'" class="flex flex-col items-center gap-3 text-center">
                  <p class="text-sm leading-6 text-slate-600">Scan QR Code ini menggunakan aplikasi e-wallet atau m-banking Anda.</p>
                  <img
                    v-if="paymentMethod.qr_image_url"
                    :src="paymentMethod.qr_image_url"
                    :alt="`QR pembayaran ${paymentMethod.name}`"
                    class="max-h-64 max-w-full rounded-lg bg-white object-contain ring-1 ring-slate-200"
                  />
                  <p v-else class="text-sm text-bad-fg" role="alert">QR Code belum dikonfigurasi untuk metode ini.</p>
                </div>
                <div v-else-if="['va', 'bank_transfer'].includes(paymentMethod.category)" class="text-sm leading-6 text-slate-700">
                  <p>Silakan transfer ke rekening atas nama <span class="font-semibold">{{ paymentMethod.account_name }}</span>.</p>
                  <p class="mt-2">Nomor rekening: <span class="font-mono font-bold">{{ paymentMethod.account_number }}</span></p>
                </div>
                <p v-else-if="paymentMethod.category === 'cod'" class="text-sm leading-6 text-slate-700">
                  Bayar pesanan secara tunai kepada kurir saat pesanan diterima.
                </p>
                <p v-else class="text-sm text-bad-fg" role="alert">Kategori metode pembayaran ini tidak didukung.</p>
              </div>
            </template>
            <p v-if="!paymentMethods.length" class="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900" role="status">
              Belum ada metode pembayaran aktif. Silakan hubungi pengelola toko.
            </p>
          </fieldset>
          <p v-if="selectedPaymentMethod" class="mt-3 text-xs leading-5 text-slate-500">Metode pembayaran akan digunakan sesuai rincian yang ditampilkan di atas.</p>
        </section>
      </div>

      <aside class="h-fit rounded-2xl border border-slate-200 bg-white p-5 shadow-sm lg:sticky lg:top-24 sm:p-6">
        <h2 class="text-base font-bold text-slate-900">Ringkasan Pesanan</h2>
        <ul class="mt-4 max-h-72 space-y-4 overflow-y-auto pr-1">
          <li v-for="item in checkoutItems" :key="item.id" class="flex gap-3">
            <div class="h-16 w-16 shrink-0 overflow-hidden rounded-xl bg-slate-100 ring-1 ring-slate-200">
              <img v-if="imageOf(item.products)" :src="imageOf(item.products)" :alt="item.products.name" class="h-full w-full object-cover" />
              <span v-else class="flex h-full items-center justify-center text-[10px] text-slate-400">Tanpa foto</span>
            </div>
            <div class="min-w-0 flex-1">
              <p class="line-clamp-2 text-sm font-medium text-slate-800">{{ item.products.name }}</p>
              <p class="mt-1 text-xs text-slate-500">{{ item.quantity }} × {{ formatRupiah(item.products.price) }}</p>
            </div>
            <p class="shrink-0 text-right text-sm font-semibold text-slate-900">{{ formatRupiah(item.products.price * item.quantity) }}</p>
          </li>
        </ul>

        <dl class="mt-5 space-y-3 border-t border-slate-100 pt-4 text-sm">
          <div class="flex justify-between gap-3"><dt class="text-slate-500">Subtotal produk</dt><dd class="text-right font-medium text-slate-800">{{ formatRupiah(checkoutSubtotal) }}</dd></div>
          <div class="flex justify-between gap-3"><dt class="text-slate-500">Pengiriman · {{ selectedShipping?.name }}</dt><dd class="text-right font-medium text-slate-800">{{ formatRupiah(shippingCost) }}</dd></div>
          <div class="flex justify-between gap-3 border-t border-slate-200 pt-3 text-base font-bold"><dt class="text-slate-900">Total pembayaran</dt><dd class="text-right text-emerald-800">{{ formatRupiah(total) }}</dd></div>
        </dl>

        <p v-if="error" class="mt-4 rounded-xl bg-bad-bg p-3 text-sm text-bad-fg" role="alert">{{ error }}</p>
        <button
          class="btn-primary mt-5 min-h-12 w-full rounded-xl text-sm font-semibold shadow-sm disabled:cursor-not-allowed disabled:opacity-50"
          type="button"
          :disabled="placing || !selected || !selectedPaymentMethodId || checkoutProblems.length > 0"
          @click="buatPesanan"
        >{{ placing ? 'Membuat pesanan…' : 'Buat pesanan' }}</button>
        <p v-if="!selected" class="mt-3 text-xs text-slate-500">Pilih atau tambahkan alamat pengiriman terlebih dahulu.</p>
        <p v-if="checkoutProblems.length" class="mt-3 text-xs text-bad-fg">Ada produk yang stoknya tidak mencukupi. <RouterLink :to="{ name: 'keranjang' }" class="underline">Perbaiki di keranjang</RouterLink>.</p>
        <p class="mt-4 text-center text-[11px] leading-5 text-slate-400">Dengan membuat pesanan, Anda menyetujui rincian checkout di atas.</p>
      </aside>
    </div>

    <div v-if="showAddressPicker && addresses.length" class="fixed inset-0 z-40 flex items-end justify-center bg-slate-950/40 p-0 sm:items-center sm:p-4" role="presentation" @click.self="showAddressPicker = false; showForm = false">
      <section class="max-h-[90vh] w-full max-w-xl overflow-y-auto rounded-t-2xl bg-white p-5 shadow-2xl sm:rounded-2xl sm:p-6" role="dialog" aria-modal="true" aria-labelledby="address-picker-title">
        <div class="flex items-center justify-between gap-3">
          <h2 id="address-picker-title" class="text-lg font-bold text-slate-900">{{ showForm ? 'Tambah alamat baru' : 'Pilih alamat pengiriman' }}</h2>
          <button class="rounded-lg p-2 text-slate-500 transition hover:bg-slate-100" type="button" aria-label="Tutup" @click="showAddressPicker = false; showForm = false">
            <svg viewBox="0 0 20 20" class="h-5 w-5" fill="currentColor" aria-hidden="true"><path d="M4.293 4.293a1 1 0 0 1 1.414 0L10 8.586l4.293-4.293a1 1 0 1 1 1.414 1.414L11.414 10l4.293 4.293a1 1 0 0 1-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 0 1-1.414-1.414L8.586 10 4.293 5.707a1 1 0 0 1 0-1.414Z" /></svg>
          </button>
        </div>

        <div v-if="!showForm" class="mt-5 space-y-3">
          <button
            v-for="address in addresses"
            :key="address.id"
            class="w-full rounded-xl border p-4 text-left transition"
            :class="selected === address.id ? 'border-emerald-600 bg-emerald-50/60 ring-1 ring-emerald-600' : 'border-slate-200 hover:border-slate-300'"
            type="button"
            @click="selected = address.id; showAddressPicker = false"
          >
            <span class="flex items-center justify-between gap-3">
              <span class="text-sm font-semibold text-slate-900">{{ address.label }} · {{ address.recipient_name }}</span>
              <span v-if="address.is_default" class="rounded-full bg-slate-100 px-2 py-0.5 text-[10px] font-medium text-slate-600">Utama</span>
            </span>
            <span class="mt-1 block text-xs text-slate-500">{{ address.phone }}</span>
            <span class="mt-1 block text-sm leading-5 text-slate-600">{{ address.street }}, {{ address.city }}, {{ address.province }} {{ address.postal_code }}</span>
          </button>
          <button class="inline-flex min-h-10 items-center gap-2 rounded-lg border border-emerald-200 px-4 text-sm font-semibold text-emerald-800 transition hover:bg-emerald-50" type="button" @click="mulaiTambahAlamat">
            <span aria-hidden="true">+</span> Tambah alamat baru
          </button>
        </div>

        <form v-else class="mt-5 grid gap-3 sm:grid-cols-2" @submit.prevent="simpanAlamat">
          <p v-if="error" class="rounded-lg bg-bad-bg p-3 text-sm text-bad-fg sm:col-span-2" role="alert">{{ error }}</p>
          <div><label for="modal-a-label" class="mb-1 block text-sm font-medium text-slate-700">Label</label><input id="modal-a-label" v-model="form.label" class="input" required /></div>
          <div><label for="modal-a-nama" class="mb-1 block text-sm font-medium text-slate-700">Nama penerima</label><input id="modal-a-nama" v-model="form.recipient_name" class="input" autocomplete="name" required /></div>
          <div><label for="modal-a-hp" class="mb-1 block text-sm font-medium text-slate-700">Nomor telepon</label><input id="modal-a-hp" :value="form.phone" class="input" type="tel" autocomplete="tel" required @input="sanitizeNumeric('phone', $event)" /></div>
          <div><label for="modal-a-prov" class="mb-1 block text-sm font-medium text-slate-700">Provinsi</label><input id="modal-a-prov" :value="form.province" class="input" required @input="sanitizeText('province', $event)" /></div>
          <div><label for="modal-a-kota" class="mb-1 block text-sm font-medium text-slate-700">Kota/Kabupaten</label><input id="modal-a-kota" :value="form.city" class="input" required @input="sanitizeText('city', $event)" /></div>
          <div><label for="modal-a-pos" class="mb-1 block text-sm font-medium text-slate-700">Kode pos</label><input id="modal-a-pos" v-model="form.postal_code" class="input" inputmode="numeric" /></div>
          <div class="sm:col-span-2"><label for="modal-a-jalan" class="mb-1 block text-sm font-medium text-slate-700">Alamat lengkap</label><input id="modal-a-jalan" v-model="form.street" class="input" autocomplete="street-address" required /></div>
          <div class="flex gap-2 sm:col-span-2">
            <button class="btn-primary rounded-lg px-4 py-2.5" type="submit" :disabled="savingAddr">{{ savingAddr ? 'Menyimpan…' : 'Simpan dan gunakan alamat' }}</button>
            <button class="btn-outline" type="button" @click="showForm = false">Kembali ke daftar alamat</button>
          </div>
        </form>
      </section>
    </div>
  </div>
</template>
