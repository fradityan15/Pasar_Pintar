<script setup>
import { onBeforeUnmount, reactive, ref } from 'vue'
import AdminPageHeader from '@/components/AdminPageHeader.vue'

const settings = reactive({
  platformName: 'PasarPintar',
  adminEmail: 'admin@pasarpintar.id',
  commissionRate: 5,
  minimumWithdrawal: 50000,
  primaryPaymentMethod: 'bank-transfer',
  buyerEmailNotifications: true,
  maintenanceMode: false,
})
const notice = ref('')
let noticeTimeout

function saveSettings() {
  clearTimeout(noticeTimeout)
  notice.value = 'Pengaturan berhasil diperbarui!'
  noticeTimeout = setTimeout(() => { notice.value = '' }, 5000)
}

onBeforeUnmount(() => clearTimeout(noticeTimeout))
</script>

<template>
  <AdminPageHeader title="Pengaturan" desc="Preferensi umum dan konfigurasi marketplace PasarPintar." />

  <section class="card w-full overflow-hidden">
    <form @submit.prevent="saveSettings">
      <div class="divide-y divide-gray-100">
        <section class="p-5 sm:p-7" aria-labelledby="general-settings-title">
          <div class="mb-6 flex items-start gap-4">
            <span class="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-gray-100 text-gray-900" aria-hidden="true">
              <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                <path d="M3 21h18M5 21V7l8-4v18M19 21V11l-6-4" /><path d="M9 9v.01M9 12v.01M9 15v.01M9 18v.01" />
              </svg>
            </span>
            <div>
              <h2 id="general-settings-title" class="text-lg font-semibold text-gray-900">Informasi umum platform</h2>
              <p class="mt-1 text-sm text-gray-600">Identitas marketplace dan aturan komisi transaksi.</p>
            </div>
          </div>

          <div class="grid grid-cols-1 gap-6 md:grid-cols-2 xl:grid-cols-3">
            <div>
              <label for="platform-name" class="mb-1.5 block text-sm font-medium text-gray-700">Nama platform</label>
              <input id="platform-name" v-model.trim="settings.platformName" class="input" required maxlength="80" />
            </div>
            <div>
              <label for="admin-email" class="mb-1.5 block text-sm font-medium text-gray-700">Email admin</label>
              <input id="admin-email" v-model.trim="settings.adminEmail" class="input" type="email" required autocomplete="email" />
            </div>
            <div class="md:col-span-2 xl:col-span-1">
              <label for="commission-rate" class="mb-1.5 block text-sm font-medium text-gray-700">Komisi platform</label>
              <div class="relative">
                <input id="commission-rate" v-model.number="settings.commissionRate" class="input pr-10" type="number" min="0" max="100" step="0.1" required />
                <span class="pointer-events-none absolute inset-y-0 right-3 flex items-center text-sm font-medium text-gray-500">%</span>
              </div>
              <p class="mt-1.5 text-xs text-gray-500">Persentase komisi dari nilai transaksi.</p>
            </div>
          </div>
        </section>

        <section class="p-5 sm:p-7" aria-labelledby="transaction-settings-title">
          <div class="mb-6 flex items-start gap-4">
            <span class="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-gray-100 text-gray-900" aria-hidden="true">
              <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                <rect x="3" y="5" width="18" height="14" rx="2" /><path d="M3 10h18M7 15h3" />
              </svg>
            </span>
            <div>
              <h2 id="transaction-settings-title" class="text-lg font-semibold text-gray-900">Pengaturan transaksi &amp; toko</h2>
              <p class="mt-1 text-sm text-gray-600">Atur batas pencairan dan metode pembayaran utama.</p>
            </div>
          </div>

          <div class="grid grid-cols-1 gap-6 md:grid-cols-2">
            <div>
              <label for="minimum-withdrawal" class="mb-1.5 block text-sm font-medium text-gray-700">Batas minimum penarikan saldo UMKM</label>
              <div class="flex min-h-[44px] overflow-hidden rounded-xl border border-line bg-white focus-within:border-gray-900 focus-within:ring-2 focus-within:ring-gray-900/10">
                <span class="flex items-center border-r border-line bg-gray-50 px-3 text-sm font-semibold text-gray-700">Rp</span>
                <input id="minimum-withdrawal" v-model.number="settings.minimumWithdrawal" class="min-w-0 flex-1 border-0 bg-transparent px-3 text-sm text-gray-900 outline-none focus:ring-0" type="number" min="0" step="5000" required />
              </div>
              <p class="mt-1.5 text-xs text-gray-500">Batas nilai sebelum mitra dapat mengajukan pencairan.</p>
            </div>
            <div>
              <label for="payment-method" class="mb-1.5 block text-sm font-medium text-gray-700">Metode pembayaran utama</label>
              <select id="payment-method" v-model="settings.primaryPaymentMethod" class="input">
                <option value="bank-transfer">Transfer Bank</option>
                <option value="manual-verification">Manual Verification</option>
              </select>
              <p class="mt-1.5 text-xs text-gray-500">Metode yang digunakan sebagai pilihan utama saat transaksi.</p>
            </div>
          </div>
        </section>

        <section class="p-5 sm:p-7" aria-labelledby="security-settings-title">
          <div class="mb-6 flex items-start gap-4">
            <span class="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-gray-100 text-gray-900" aria-hidden="true">
              <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                <path d="M12 22s8-4 8-11V5l-8-3-8 3v6c0 7 8 11 8 11Z" /><path d="m9 12 2 2 4-4" />
              </svg>
            </span>
            <div>
              <h2 id="security-settings-title" class="text-lg font-semibold text-gray-900">Notifikasi &amp; keamanan sistem</h2>
              <p class="mt-1 text-sm text-gray-600">Kelola komunikasi pembeli dan ketersediaan platform.</p>
            </div>
          </div>

          <div class="divide-y divide-gray-100">
            <label for="buyer-email-notifications" class="flex cursor-pointer items-center justify-between gap-5 py-4 first:pt-0 last:pb-0">
              <span>
                <span class="block text-sm font-medium text-gray-900">Notifikasi email otomatis ke pembeli</span>
                <span class="mt-1 block text-xs leading-5 text-gray-500">Kirim pemberitahuan email untuk pembaruan pesanan.</span>
              </span>
              <span class="relative inline-flex shrink-0">
                <input id="buyer-email-notifications" v-model="settings.buyerEmailNotifications" class="peer sr-only" type="checkbox" role="switch" />
                <span class="h-6 w-11 rounded-full bg-gray-300 transition-colors peer-checked:bg-gray-900 peer-focus-visible:outline peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-gray-900"></span>
                <span class="pointer-events-none absolute left-1 top-1 h-4 w-4 rounded-full bg-white shadow-sm transition-transform peer-checked:translate-x-5"></span>
              </span>
            </label>

            <label for="maintenance-mode" class="flex cursor-pointer items-center justify-between gap-5 py-4">
              <span>
                <span class="block text-sm font-medium text-gray-900">Mode pemeliharaan</span>
                <span class="mt-1 block text-xs leading-5 text-gray-500">Tandai platform sedang dalam pemeliharaan.</span>
              </span>
              <span class="relative inline-flex shrink-0">
                <input id="maintenance-mode" v-model="settings.maintenanceMode" class="peer sr-only" type="checkbox" role="switch" />
                <span class="h-6 w-11 rounded-full bg-gray-300 transition-colors peer-checked:bg-gray-900 peer-focus-visible:outline peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-gray-900"></span>
                <span class="pointer-events-none absolute left-1 top-1 h-4 w-4 rounded-full bg-white shadow-sm transition-transform peer-checked:translate-x-5"></span>
              </span>
            </label>
          </div>
        </section>
      </div>

      <div class="flex flex-wrap items-center justify-between gap-4 border-t border-line bg-gray-50/70 px-5 py-4 sm:px-7">
        <p class="text-xs text-gray-500">Perubahan berlaku untuk konfigurasi platform.</p>
        <button class="btn-primary" type="submit">Simpan Perubahan</button>
      </div>
    </form>
  </section>
  <p v-if="notice" class="fixed bottom-5 right-5 z-50 max-w-sm rounded-xl border border-gray-700 bg-gray-900 px-4 py-3 text-sm text-white shadow-xl" role="status" aria-live="polite">
    {{ notice }}
  </p>
</template>
