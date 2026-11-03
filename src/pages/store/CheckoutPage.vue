<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { RouterLink, useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useCartStore } from '@/stores/cart'
import { createOrder, listActivePaymentMethods, listAddresses, saveAddress } from '@/services/orderService'
import { formatRupiah } from '@/lib/format'
import { supabase } from '@/lib/supabase'
import { claimVoucher, listMyVoucherClaims } from '@/services/voucherService'
import { loadMyLoyaltyWallet } from '@/services/loyaltyService'
import RajaOngkirAreaPicker from '@/components/RajaOngkirAreaPicker.vue'

const auth = useAuthStore()
const cart = useCartStore()
const route = useRoute()
const router = useRouter()

const addresses = ref([])
const selected = ref(null)
const paymentMethods = ref([])
const shippingQuote = ref(null)
const shippingOptions = ref([])
const selectedShippingOptionId = ref('')
const shippingLoading = ref(false)
const shippingError = ref('')
let shippingRequestId = 0
const selectedPaymentMethodId = ref(null)
const paymentMethodsExpanded = ref(false)
const voucherClaims = ref([])
const voucherCode = ref('')
const voucherClaim = ref(null)
const voucherError = ref('')
const voucherNotice = ref('')
const claimingVoucher = ref(false)
const loyaltyWallet = ref(null)
const loyaltyError = ref('')
const redeemPoints = ref(0)
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
  rajaongkir_area_id: '',
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
const voucherEligibleSubtotal = computed(() => {
  if (!voucherClaim.value) return 0
  return checkoutItems.value.reduce((subtotal, item) => {
    const product = item.products
    const eligible = voucherClaim.value.scope_type === 'all'
      || (voucherClaim.value.scope_type === 'stores' && voucherClaim.value.umkm_ids?.includes(product.umkm?.id))
      || (voucherClaim.value.scope_type === 'categories' && voucherClaim.value.category_ids?.includes(product.category_id))
    return subtotal + (eligible ? Number(product.price) * item.quantity : 0)
  }, 0)
})
const voucherDiscountPreview = computed(() => {
  const voucher = voucherClaim.value
  if (!voucher || voucherEligibleSubtotal.value < Number(voucher.minimum_purchase)) return 0
  const discount = voucher.discount_type === 'nominal'
    ? Number(voucher.discount_value)
    : Math.round(voucherEligibleSubtotal.value * Number(voucher.discount_value) / 100)
  return Math.min(
    discount,
    voucher.maximum_discount == null ? Number.MAX_SAFE_INTEGER : Number(voucher.maximum_discount),
    voucherEligibleSubtotal.value,
  )
})
const selectedAddress = computed(() => addresses.value.find((address) => address.id === selected.value) ?? null)
const selectedPaymentMethod = computed(() =>
  paymentMethods.value.find((paymentMethod) => paymentMethod.id === selectedPaymentMethodId.value) ?? null,
)
const sortedPaymentMethods = computed(() =>
  [...paymentMethods.value].sort((left, right) => {
    const priority = (method) => method.provider === 'midtrans' ? 0 : method.category === 'cod' ? 2 : 1
    return priority(left) - priority(right) || left.name.localeCompare(right.name)
  }),
)

const selectedShipping = computed(() => shippingOptions.value.find((option) => option.id === selectedShippingOptionId.value))
const shippingCost = computed(() => selectedShipping.value?.shipping_cost ?? 0)
const totalBeforePoints = computed(() => checkoutSubtotal.value + shippingCost.value - voucherDiscountPreview.value)
const maxRedeemPoints = computed(() => {
  if (!loyaltyWallet.value?.settings || totalBeforePoints.value <= 0) return 0
  const { max_redeem_points_per_order: configuredLimit, redemption_value } = loyaltyWallet.value.settings
  const orderLimit = totalBeforePoints.value > 0
    ? Math.floor((totalBeforePoints.value - 1) / Number(redemption_value))
    : 0
  return Math.max(0, Math.min(
    Number(loyaltyWallet.value.balance),
    configuredLimit == null ? Number.MAX_SAFE_INTEGER : Number(configuredLimit),
    orderLimit,
  ))
})
const pointsDiscountPreview = computed(() => {
  if (!loyaltyWallet.value?.settings) return 0
  return Math.min(
    Math.max(0, Number(redeemPoints.value) || 0) * Number(loyaltyWallet.value.settings.redemption_value),
    totalBeforePoints.value,
  )
})
const total = computed(() => totalBeforePoints.value - pointsDiscountPreview.value)

async function loadShippingRates() {
  const currentRequestId = ++shippingRequestId
  shippingQuote.value = null
  shippingOptions.value = []
  selectedShippingOptionId.value = ''
  shippingError.value = ''
  if (!selected.value || !selectedProductIds.value.length) {
    shippingLoading.value = false
    return
  }

  const addressId = typeof selected.value === 'string' ? selected.value.trim() : ''
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(addressId) || !selectedAddress.value) {
    shippingError.value = 'Pilih alamat pengiriman tersimpan yang valid untuk menghitung ongkir.'
    shippingLoading.value = false
    return
  }

  shippingLoading.value = true
  try {
    const storedDestinationAreaId = typeof selectedAddress.value.rajaongkir_area_id === 'string'
      ? selectedAddress.value.rajaongkir_area_id.trim()
      : ''
    if (!storedDestinationAreaId) {
      throw new Error('Pilih wilayah tujuan RajaOngkir pada alamat pengiriman terlebih dahulu.')
    }
    console.log('RajaOngkir rates request destination', {
      address_id: addressId,
      destination_area_id: storedDestinationAreaId,
    })
    const { data, error: invokeError } = await supabase.functions.invoke('rajaongkir-rates', {
      body: {
        address_id: addressId,
        product_ids: selectedProductIds.value,
      },
    })
    if (invokeError) {
      const response = invokeError.context
      let responseMessage = ''
      if (response instanceof Response) {
        const responseBody = await response.clone().json().catch(() => null)
        if (typeof responseBody?.error === 'string') responseMessage = responseBody.error
        console.error('Gagal menghitung tarif RajaOngkir:', {
          status: response.status,
          body: responseBody ?? await response.clone().text(),
        })
      } else {
        console.error('Gagal memanggil fungsi rajaongkir-rates:', invokeError)
      }
      throw new Error(responseMessage || data?.error || 'Tarif pengiriman tidak tersedia. Coba lagi nanti.')
    }
    if (!data) {
      throw new Error(data?.error || 'Tarif pengiriman tidak tersedia. Coba lagi nanti.')
    }
    if (typeof data.quote_id !== 'string' || !Array.isArray(data.options) || !data.options.length) {
      throw new Error('Tidak ada layanan kurir yang tersedia untuk alamat ini.')
    }
    const optionsAreValid = data.options.every((option) =>
      option &&
      typeof option.id === 'string' &&
      Number.isSafeInteger(option.shipping_cost) &&
      Array.isArray(option.shipments) &&
      option.shipments.length > 0 &&
      option.shipments.every((shipment) =>
        typeof shipment.umkm_id === 'string' &&
        typeof shipment.seller_name === 'string' &&
        typeof shipment.courier_name === 'string' &&
        typeof shipment.service_name === 'string',
      ),
    )
    if (!optionsAreValid) throw new Error('Respons tarif pengiriman tidak valid. Coba hitung ulang.')
    if (currentRequestId === shippingRequestId) {
      shippingQuote.value = data.quote_id
      shippingOptions.value = data.options
      selectedShippingOptionId.value = data.options[0].id
    }
  } catch (rateError) {
    if (currentRequestId === shippingRequestId) {
      shippingError.value = rateError.message || 'Tarif pengiriman tidak dapat dihitung.'
    }
  } finally {
    if (currentRequestId === shippingRequestId) shippingLoading.value = false
  }
}

onMounted(async () => {
  try {
    await cart.load()
    addresses.value = await listAddresses()
    paymentMethods.value = await listActivePaymentMethods()
    voucherClaims.value = await listMyVoucherClaims()
    try {
      loyaltyWallet.value = await loadMyLoyaltyWallet()
    } catch (loyaltyLoadError) {
      loyaltyError.value = loyaltyLoadError.message || 'Poin belum dapat dimuat; checkout tetap dapat dilakukan tanpa menukar poin.'
    }
    selected.value = addresses.value.find((address) => address.is_default)?.id ?? addresses.value[0]?.id ?? null
    showForm.value = addresses.value.length === 0
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
})

watch(
  [selected, () => selectedProductIds.value.join(',')],
  () => { loadShippingRates() },
)

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
    if (!form.rajaongkir_area_id.trim()) {
      throw new Error('Pilih wilayah pengiriman dari hasil pencarian RajaOngkir.')
    }
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

async function klaimVoucher() {
  claimingVoucher.value = true
  voucherError.value = ''
  voucherNotice.value = ''
  try {
    const claimed = await claimVoucher(voucherCode.value)
    voucherClaim.value = claimed
    voucherCode.value = ''
    voucherClaims.value = await listMyVoucherClaims()
    voucherNotice.value = `Voucher ${claimed.code} berhasil diklaim.`
  } catch (claimError) {
    voucherError.value = claimError.message || 'Voucher tidak dapat diklaim.'
  } finally {
    claimingVoucher.value = false
  }
}

function pilihKlaimVoucher(claimId) {
  voucherError.value = ''
  voucherNotice.value = ''
  voucherClaim.value = voucherClaims.value.find((claim) => claim.claim_id === claimId) ?? null
}

async function buatPesanan() {
  placing.value = true
  error.value = ''
  try {
    const paymentMethodId = selectedPaymentMethod.value?.id
    if (!paymentMethodId) throw new Error('Pilih metode pembayaran terlebih dahulu')
    if (!Number.isInteger(Number(redeemPoints.value)) || Number(redeemPoints.value) < 0) {
      throw new Error('Masukkan jumlah poin bulat yang valid.')
    }
    if (Number(redeemPoints.value) > maxRedeemPoints.value) {
      throw new Error('Penukaran poin melebihi saldo atau batas pesanan.')
    }
    if (!shippingQuote.value || !selectedShippingOptionId.value) {
      throw new Error(shippingError.value || 'Pilih tarif pengiriman yang valid sebelum membuat pesanan.')
    }
    const orderId = await createOrder(
      selected.value,
      paymentMethodId,
      selectedProductIds.value,
      shippingQuote.value,
      selectedShippingOptionId.value,
      voucherClaim.value?.claim_id ?? null,
      Number(redeemPoints.value) || 0,
    )
    const selectedIds = new Set(selectedProductIds.value)
    cart.items = cart.items.filter((item) => !selectedIds.has(item.product_id))
    await router.push({ name: 'payment', params: { orderId } })
  } catch (e) {
    error.value = e.message
    await cart.load()
    if (/tarif pengiriman|keranjang berubah|quote/i.test(e.message)) await loadShippingRates()
  } finally {
    placing.value = false
  }
}
</script>

<template>
  <div class="mx-auto max-w-7xl px-4 pb-16 pt-8 md:px-6 lg:px-8">
    <RouterLink :to="{ name: 'keranjang' }" class="inline-flex items-center gap-2 text-sm font-medium text-slate-500 transition hover:text-gray-900">
      <span aria-hidden="true">←</span> Kembali ke keranjang
    </RouterLink>
    <div class="mt-3">
      <p class="text-sm font-medium text-indigo-700">Satu langkah lagi menuju pesanan Anda</p>
      <h1 class="mt-1 text-3xl font-bold text-slate-900">Checkout</h1>
    </div>

    <div v-if="loading" class="mt-6 grid gap-6 lg:grid-cols-[minmax(0,1fr)_360px]">
      <div class="h-[480px] animate-pulse rounded-2xl bg-surface"></div>
      <div class="h-72 animate-pulse rounded-2xl bg-surface"></div>
    </div>

    <div v-else-if="!checkoutItems.length" class="mt-6 rounded-2xl border border-slate-200 bg-white p-10 text-center shadow-sm">
      <p class="font-semibold text-slate-900">Tidak ada barang terpilih untuk di-checkout</p>
      <RouterLink :to="{ name: 'keranjang' }" class="btn bg-gray-900 text-white transition-colors hover:bg-black hover:shadow-md mt-5 inline-flex rounded-xl px-6 py-3">Kembali ke keranjang</RouterLink>
    </div>

    <div v-else class="mt-6 grid items-start gap-6 lg:grid-cols-[minmax(0,1fr)_360px] lg:gap-8">
      <div class="flex min-w-0 flex-col gap-5">
        <section class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm sm:p-6">
          <div class="flex items-start gap-3">
            <span class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-indigo-50 text-indigo-700" aria-hidden="true">
              <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="1.8"><path stroke-linecap="round" stroke-linejoin="round" d="M20 10c0 5-8 11-8 11S4 15 4 10a8 8 0 1 1 16 0Z" /><circle cx="12" cy="10" r="2.5" /></svg>
            </span>
            <div class="min-w-0 flex-1">
              <h2 class="text-base font-bold text-slate-900">Alamat Pengiriman</h2>
              <template v-if="selectedAddress">
                <p class="mt-3 text-sm font-semibold text-slate-900">{{ selectedAddress.label }} <span class="font-normal text-slate-500">· {{ selectedAddress.recipient_name }}</span></p>
                <p class="mt-1 text-sm text-slate-600">{{ selectedAddress.phone }}</p>
                <p class="mt-1 text-sm leading-6 text-slate-600">{{ selectedAddress.street }}, {{ selectedAddress.city }}, {{ selectedAddress.province }} {{ selectedAddress.postal_code }}</p>
                <p v-if="!selectedAddress.rajaongkir_area_id" class="mt-2 text-sm text-amber-800">
                  Wilayah tujuan RajaOngkir belum dipilih.
                  <RouterLink :to="{ name: 'akun' }" class="font-semibold underline">Lengkapi alamat di Akun</RouterLink>
                </p>
              </template>
              <p v-else class="mt-3 text-sm text-slate-500">Tambahkan alamat untuk melanjutkan checkout.</p>
              <button
                v-if="addresses.length"
                class="mt-4 inline-flex min-h-10 items-center justify-center rounded-lg border border-gray-900 px-4 text-sm font-semibold text-gray-900 transition hover:bg-gray-50"
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
            <div class="sm:col-span-2">
              <RajaOngkirAreaPicker id="a-area" v-model="form.rajaongkir_area_id" />
              <p class="mt-1 text-xs text-slate-500">Tarif hanya dapat dihitung setelah kode area tujuan terisi.</p>
            </div>
            <div class="sm:col-span-2"><label for="a-jalan" class="mb-1 block text-sm font-medium text-slate-700">Alamat lengkap</label><input id="a-jalan" v-model="form.street" class="input" autocomplete="street-address" required /></div>
            <div class="flex gap-2 sm:col-span-2">
              <button class="btn bg-gray-900 text-white transition-colors hover:bg-black hover:shadow-md rounded-lg px-4 py-2.5" type="submit" :disabled="savingAddr">{{ savingAddr ? 'Menyimpan…' : 'Simpan dan gunakan alamat' }}</button>
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
              :class="selectedShippingOptionId === option.id ? 'border-gray-900 bg-gray-50/60 ring-1 ring-gray-900' : 'border-slate-200 hover:border-slate-300'"
            >
              <input v-model="selectedShippingOptionId" type="radio" name="pengiriman" :value="option.id" class="mt-1 h-4 w-4 border-slate-300 text-gray-900 focus:ring-gray-900 accent-gray-900" />
              <span class="min-w-0 flex-1">
                <span class="flex items-center justify-between gap-2">
                  <span class="text-sm font-semibold text-slate-900">{{ option.shipments.map((shipment) => `${shipment.seller_name}: ${shipment.courier_name} ${shipment.service_name}`).join(' · ') }}</span>
                  <span class="text-sm font-bold text-gray-900">{{ formatRupiah(option.shipping_cost) }}</span>
                </span>
                <span v-for="shipment in option.shipments" :key="shipment.umkm_id" class="mt-1 block text-xs text-slate-500">
                  {{ shipment.seller_name }} · {{ shipment.duration || 'estimasi mengikuti kurir' }}
                </span>
              </span>
            </label>
          </fieldset>
          <p v-if="shippingLoading" class="mt-3 text-sm text-slate-500" role="status">Menghitung tarif langsung dari RajaOngkir…</p>
          <p v-if="shippingError" class="mt-3 rounded-lg bg-amber-50 p-3 text-sm text-amber-900" role="alert">
            {{ shippingError }}
            <button type="button" class="ml-1 font-semibold underline" :disabled="shippingLoading" @click="loadShippingRates">Coba lagi</button>
          </p>
        </section>

        <section class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm sm:p-6">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h2 class="text-base font-bold text-slate-900">Metode Pembayaran</h2>
          </div>
          <button
            type="button"
            class="mt-4 flex w-full items-center justify-between gap-3 rounded-xl border border-slate-200 bg-white p-4 text-left transition-colors hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-gray-900"
            aria-controls="payment-method-options"
            :aria-expanded="paymentMethodsExpanded"
            @click="paymentMethodsExpanded = !paymentMethodsExpanded"
          >
            <span>
              <span class="block text-sm font-semibold text-slate-900">Pilih Metode Pembayaran</span>
              <span class="mt-1 block text-xs text-slate-500">
                {{ selectedPaymentMethod?.name ?? 'Pilih salah satu metode' }}
              </span>
            </span>
            <svg
              viewBox="0 0 20 20"
              class="h-5 w-5 shrink-0 text-slate-600 transition-transform"
              :class="{ 'rotate-180': paymentMethodsExpanded }"
              fill="currentColor"
              aria-hidden="true"
            >
              <path fill-rule="evenodd" d="M5.22 7.47a.75.75 0 0 1 1.06 0L10 11.19l3.72-3.72a.75.75 0 1 1 1.06 1.06l-4.25 4.25a.75.75 0 0 1-1.06 0L5.22 8.53a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" />
            </svg>
          </button>
          <fieldset v-if="paymentMethodsExpanded" id="payment-method-options" class="mt-3 space-y-3">
            <legend class="sr-only">Pilih metode pembayaran</legend>
            <label
              v-for="paymentMethod in sortedPaymentMethods"
              :key="paymentMethod.id"
              class="flex cursor-pointer items-center gap-4 rounded-xl border p-4 transition-colors hover:bg-slate-50"
              :class="selectedPaymentMethodId === paymentMethod.id ? 'border-gray-900 bg-gray-50 ring-1 ring-gray-900' : 'border-slate-200'"
            >
              <input v-model="selectedPaymentMethodId" type="radio" name="metode" :value="paymentMethod.id" class="h-4 w-4 border-slate-300 text-gray-900 focus:ring-gray-900 accent-gray-900" />
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
                <span v-if="paymentMethod.provider === 'midtrans'" class="mt-1 block text-xs text-indigo-700">Pembayaran otomatis via Midtrans Sandbox</span>
                <span v-else-if="['va', 'bank_transfer', 'qris'].includes(paymentMethod.category)" class="mt-1 block text-xs text-slate-500">Transfer manual · diverifikasi admin</span>
              </span>
            </label>
            <p v-if="!paymentMethods.length" class="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900" role="status">
              Belum ada metode pembayaran aktif. Silakan hubungi pengelola toko.
            </p>
          </fieldset>

          <div v-if="selectedPaymentMethod" class="mt-3 rounded-xl border border-indigo-100 bg-indigo-50/50 p-4">
            <div v-if="selectedPaymentMethod.provider === 'midtrans'" class="text-sm leading-6 text-slate-700">
              <p v-if="selectedPaymentMethod.category === 'qris'">QRIS dinamis akan dibuat setelah pesanan dikonfirmasi. Pembayaran akan diverifikasi otomatis oleh Midtrans.</p>
              <p v-else>Nomor Virtual Account unik akan dibuat setelah pesanan dikonfirmasi. Pembayaran akan diverifikasi otomatis oleh Midtrans.</p>
            </div>
            <div v-else-if="selectedPaymentMethod.category === 'qris'" class="flex flex-col items-center gap-3 text-center">
              <p class="text-sm leading-6 text-slate-600">Scan QR Code ini menggunakan aplikasi e-wallet atau m-banking Anda.</p>
              <img
                v-if="selectedPaymentMethod.qr_image_url"
                :src="selectedPaymentMethod.qr_image_url"
                :alt="`QR pembayaran ${selectedPaymentMethod.name}`"
                class="max-h-64 max-w-full rounded-lg bg-white object-contain ring-1 ring-slate-200"
              />
              <p v-else class="text-sm text-bad-fg" role="alert">QR Code belum dikonfigurasi untuk metode ini.</p>
            </div>
            <div v-else-if="['va', 'bank_transfer'].includes(selectedPaymentMethod.category)" class="text-sm leading-6 text-slate-700">
              <p>Silakan transfer ke rekening atas nama <span class="font-semibold">{{ selectedPaymentMethod.account_name }}</span>.</p>
              <p class="mt-2">Nomor rekening: <span class="font-mono font-bold">{{ selectedPaymentMethod.account_number }}</span></p>
            </div>
            <p v-else-if="selectedPaymentMethod.category === 'cod'" class="text-sm leading-6 text-slate-700">
              Bayar pesanan secara tunai kepada kurir saat pesanan diterima.
            </p>
            <p v-else class="text-sm text-bad-fg" role="alert">Kategori metode pembayaran ini tidak didukung.</p>
          </div>
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
              <p class="mt-1 text-xs font-bold text-gray-900">{{ item.quantity }} × {{ formatRupiah(item.products.price) }}</p>
            </div>
            <p class="shrink-0 text-right text-sm font-bold text-gray-900">{{ formatRupiah(item.products.price * item.quantity) }}</p>
          </li>
        </ul>

        <dl class="mt-5 space-y-3 border-t border-slate-100 pt-4 text-sm">
          <div class="flex justify-between gap-3"><dt class="text-slate-500">Subtotal produk</dt><dd class="text-right font-bold text-gray-900">{{ formatRupiah(checkoutSubtotal) }}</dd></div>
          <div class="flex justify-between gap-3"><dt class="text-slate-500">Pengiriman · {{ selectedShipping?.name }}</dt><dd class="text-right font-bold text-gray-900">{{ formatRupiah(shippingCost) }}</dd></div>
          <div v-if="voucherClaim" class="flex justify-between gap-3"><dt class="text-slate-500">Diskon voucher · {{ voucherClaim.code }}</dt><dd class="text-right font-bold text-emerald-700">−{{ formatRupiah(voucherDiscountPreview) }}</dd></div>
          <div v-if="Number(redeemPoints) > 0" class="flex justify-between gap-3"><dt class="text-slate-500">Tukar poin · {{ redeemPoints }} poin</dt><dd class="text-right font-bold text-emerald-700">−{{ formatRupiah(pointsDiscountPreview) }}</dd></div>
          <div class="flex justify-between gap-3 border-t border-slate-200 pt-3 text-base font-bold"><dt class="text-slate-900">Total pembayaran</dt><dd class="text-right font-bold text-gray-900">{{ formatRupiah(total) }}</dd></div>
        </dl>

        <section v-if="loyaltyWallet" class="mt-5 border-t border-slate-100 pt-4" aria-labelledby="loyalty-checkout-title">
          <h2 id="loyalty-checkout-title" class="text-sm font-bold text-slate-900">Tukar poin loyalitas</h2>
          <p class="mt-1 text-xs text-slate-600">
            Saldo {{ loyaltyWallet.balance }} poin · {{ formatRupiah(loyaltyWallet.settings.redemption_value) }} per poin ·
            maksimal {{ maxRedeemPoints }} poin untuk pesanan ini.
          </p>
          <label for="checkout-redeem-points" class="mt-3 block text-xs font-medium text-slate-700">Poin yang digunakan</label>
          <input id="checkout-redeem-points" v-model.number="redeemPoints" class="input mt-1 w-full" type="number" min="0" :max="maxRedeemPoints" step="1" :disabled="maxRedeemPoints === 0" />
          <p v-if="Number(redeemPoints) > maxRedeemPoints" class="mt-2 text-xs text-bad-fg" role="alert">Jumlah tukar melebihi saldo atau batas pesanan.</p>
          <p class="mt-2 text-[11px] leading-5 text-slate-500">Poin dipotong saat checkout berhasil. Jika pesanan dibatalkan/refund, penukaran dan poin yang diperoleh dari pesanan akan dibalik.</p>
        </section>
        <p v-else-if="loyaltyError" class="mt-5 rounded-xl bg-amber-50 p-3 text-xs text-amber-900" role="status">{{ loyaltyError }}</p>

        <section class="mt-5 border-t border-slate-100 pt-4" aria-labelledby="voucher-checkout-title">
          <h2 id="voucher-checkout-title" class="text-sm font-bold text-slate-900">Voucher subsidi GBBI</h2>
          <form class="mt-2 flex gap-2" @submit.prevent="klaimVoucher">
            <label for="checkout-voucher-code" class="sr-only">Kode voucher</label>
            <input id="checkout-voucher-code" v-model="voucherCode" class="input min-w-0 flex-1 uppercase" maxlength="80" placeholder="Masukkan kode voucher" :disabled="claimingVoucher" />
            <button class="btn-outline shrink-0" type="submit" :disabled="claimingVoucher || !voucherCode.trim()">{{ claimingVoucher ? 'Memeriksa…' : 'Klaim' }}</button>
          </form>
          <label v-if="voucherClaims.some((claim) => claim.claim_status === 'claimed')" class="mt-3 block text-xs font-medium text-slate-700">
            Atau gunakan voucher yang sudah diklaim
            <select class="input mt-1 w-full text-sm" :value="voucherClaim?.claim_id ?? ''" @change="pilihKlaimVoucher($event.target.value)">
              <option value="">Tanpa voucher</option>
              <option v-for="claim in voucherClaims.filter((item) => item.claim_status === 'claimed')" :key="claim.claim_id" :value="claim.claim_id">{{ claim.code }}</option>
            </select>
          </label>
          <p v-if="voucherClaim && voucherEligibleSubtotal < Number(voucherClaim.minimum_purchase)" class="mt-2 text-xs text-amber-800" role="status">
            Belanja yang memenuhi cakupan voucher belum mencapai minimal {{ formatRupiah(voucherClaim.minimum_purchase) }}. Diskon hanya dapat dipakai setelah syarat terpenuhi.
          </p>
          <p v-if="voucherClaim && voucherEligibleSubtotal >= Number(voucherClaim.minimum_purchase)" class="mt-2 text-xs text-slate-500">
            Pratinjau diskon; nilai final dihitung dan divalidasi kembali oleh server.
          </p>
          <p v-if="voucherError" class="mt-2 text-xs text-bad-fg" role="alert">{{ voucherError }}</p>
          <p v-if="voucherNotice" class="mt-2 text-xs text-ok-fg" role="status">{{ voucherNotice }}</p>
          <p class="mt-2 text-[11px] leading-5 text-slate-500">Klaim mencadangkan kuota. Kuota dikembalikan jika pesanan dibatalkan atau pembayaran kedaluwarsa.</p>
        </section>

        <p v-if="error" class="mt-4 rounded-xl bg-bad-bg p-3 text-sm text-bad-fg" role="alert">{{ error }}</p>
        <button
          class="btn bg-gray-900 text-white transition-colors hover:bg-black hover:shadow-md mt-5 min-h-12 w-full rounded-xl text-sm font-semibold shadow-sm disabled:cursor-not-allowed disabled:opacity-50"
          type="button"
          :disabled="placing || shippingLoading || !shippingQuote || !selectedShippingOptionId || !selected || !selectedPaymentMethodId || checkoutProblems.length > 0 || Number(redeemPoints) > maxRedeemPoints"
          @click="buatPesanan"
        >{{ placing ? 'Membuat pesanan…' : 'Buat pesanan' }}</button>
        <p v-if="!selected" class="mt-3 text-xs text-slate-500">Pilih atau tambahkan alamat pengiriman terlebih dahulu.</p>
        <p v-if="!shippingQuote && !shippingLoading" class="mt-3 text-xs text-slate-500">Checkout hanya dapat dilanjutkan setelah tarif kurir aktual berhasil dihitung.</p>
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
            :class="selected === address.id ? 'border-gray-900 bg-gray-50/60 ring-1 ring-gray-900' : 'border-slate-200 hover:border-slate-300'"
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
          <button class="inline-flex min-h-10 items-center gap-2 rounded-lg border border-gray-900 px-4 text-sm font-semibold text-gray-900 transition hover:bg-gray-50" type="button" @click="mulaiTambahAlamat">
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
            <button class="btn bg-gray-900 text-white transition-colors hover:bg-black hover:shadow-md rounded-lg px-4 py-2.5" type="submit" :disabled="savingAddr">{{ savingAddr ? 'Menyimpan…' : 'Simpan dan gunakan alamat' }}</button>
            <button class="btn-outline" type="button" @click="showForm = false">Kembali ke daftar alamat</button>
          </div>
        </form>
      </section>
    </div>
  </div>
</template>
