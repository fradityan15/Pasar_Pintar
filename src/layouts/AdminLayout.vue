<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { RouterLink, RouterView, useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { formatRupiah, formatTanggalJam } from '@/lib/format'
import {
  listAdminPaymentNotifications,
  markAdminPaymentNotificationRead,
} from '@/services/adminOrderService'

const auth = useAuthStore()
const router = useRouter()
const sidebarExpanded = ref(true)
const mobileSidebarOpen = ref(false)
const sidebarHovered = ref(false)
const notificationsOpen = ref(false)
const notifications = ref([])
const notificationError = ref('')
let notificationTimer
const sidebarVisible = computed(() => sidebarExpanded.value || mobileSidebarOpen.value || sidebarHovered.value)
const visibleMenu = computed(() => menu.filter((item) => !item.superAdminOnly || auth.isSuperAdmin))
const unreadNotificationCount = computed(() => notifications.value.filter((item) => !item.is_read).length)

const menu = [
  { label: 'Ringkasan', to: { name: 'admin-dashboard' }, icon: 'M4 4h7v7H4zM13 4h7v7h-7zM4 13h7v7H4zM13 13h7v7h-7z' },
  { label: 'Pesanan', to: { name: 'admin-pesanan' }, icon: 'M6 3h12v18l-3-2-3 2-3-2-3 2zM9 8h6M9 12h6' },
  { label: 'Produk', to: { name: 'admin-produk' }, icon: 'M3 8l9-5 9 5v8l-9 5-9-5zM3 8l9 5 9-5M12 13v8' },
  { label: 'Kategori', to: { name: 'admin-kategori' }, icon: 'M4 4h7l9 9-7 7-9-9z' },
  { label: 'UMKM', to: { name: 'admin-umkm' }, icon: 'M4 10l1-5h14l1 5M5 10v10h14V10M9 20v-5h6v5' },
  { label: 'Keuangan', to: { name: 'admin-keuangan' }, icon: 'M3 7h18v13H3zM3 7l2-3h14l2 3M16 13h2M7 11h4' },
  { label: 'Voucher GBBI', to: { name: 'admin-voucher-gbbi' }, icon: 'M20 12v8H4v-8m16 0V8H4v4m16 0H4m8 0v8m0-12a2.5 2.5 0 1 0-5 0h5Zm0 0a2.5 2.5 0 1 1 5 0h-5Z' },
  { label: 'Pengguna', to: { name: 'admin-pengguna' }, icon: 'M12 12a4 4 0 100-8 4 4 0 000 8zM4 21c1-4 4-6 8-6s7 2 8 6' },
  { label: 'Laporan', to: { name: 'admin-laporan' }, icon: 'M5 20V10M12 20V4M19 20v-7' },
  { label: 'Audit Log', to: { name: 'admin-audit-log' }, icon: 'M12 8v4l3 2m6-2a9 9 0 11-18 0 9 9 0 0118 0Z', superAdminOnly: true },
  { label: 'Ekspor SIKP', to: { name: 'admin-sikp' }, icon: 'M12 3v12m0 0 4-4m-4 4-4-4M5 17v4h14v-4', superAdminOnly: true },
  { label: 'Manajemen Konten', to: { name: 'admin-konten' }, icon: 'M4 4h16v16H4zM4 15l4-4 4 4 3-3 5 5M9 9h.01' },
  { label: 'Pengaturan', to: { name: 'admin-pengaturan' }, icon: 'M12 8a4 4 0 100 8 4 4 0 000-8zM19.4 15l.1.1a1.7 1.7 0 11-2.4 2.4l-.1-.1a1.7 1.7 0 00-2.9 1.2v.2a1.7 1.7 0 11-3.4 0v-.2a1.7 1.7 0 00-2.9-1.2l-.1.1a1.7 1.7 0 11-2.4-2.4l.1-.1a1.7 1.7 0 00-1.2-2.9H4a1.7 1.7 0 110-3.4h.2a1.7 1.7 0 001.2-2.9l-.1-.1a1.7 1.7 0 112.4-2.4l.1.1a1.7 1.7 0 002.9-1.2V2a1.7 1.7 0 113.4 0v.2a1.7 1.7 0 002.9 1.2l.1-.1a1.7 1.7 0 112.4 2.4l.1.1a1.7 1.7 0 001.2 2.9h.2a1.7 1.7 0 110 3.4h-.2a1.7 1.7 0 00-1.2 2.9Z', separator: true },
]

async function keluar() {
  await auth.signOut()
  router.push({ name: 'login' })
}

async function loadPaymentNotifications() {
  try {
    notifications.value = await listAdminPaymentNotifications() ?? []
    notificationError.value = ''
  } catch (error) {
    notificationError.value = error.message || 'Notifikasi pembayaran tidak dapat dimuat.'
  }
}

async function openPaymentNotification(notification) {
  notificationError.value = ''
  try {
    if (!notification.is_read) {
      await markAdminPaymentNotificationRead(notification.id)
      notification.is_read = true
    }
    notificationsOpen.value = false
    await router.push({ name: 'admin-pesanan-detail', params: { id: notification.order_id } })
  } catch (error) {
    notificationError.value = error.message || 'Notifikasi tidak dapat dibuka.'
  }
}

onMounted(() => {
  loadPaymentNotifications()
  notificationTimer = window.setInterval(loadPaymentNotifications, 30_000)
})

onBeforeUnmount(() => {
  window.clearInterval(notificationTimer)
})
</script>

<template>
  <div class="flex min-h-screen bg-surface">
    <button
      v-if="mobileSidebarOpen"
      class="fixed inset-0 z-30 bg-black/30 lg:hidden"
      type="button"
      aria-label="Tutup menu"
      @click="mobileSidebarOpen = false"
    ></button>
    <aside
      @mouseenter="sidebarHovered = true"
      @mouseleave="sidebarHovered = false"
      :class="[
        'z-40 flex h-screen shrink-0 flex-col gap-1 overflow-y-auto bg-surface p-4 transition-[width] duration-200',
        mobileSidebarOpen ? 'fixed inset-y-0 left-0 w-60 shadow-xl lg:sticky lg:top-0 lg:shadow-none' : 'hidden lg:sticky lg:top-0 lg:flex',
        sidebarVisible ? 'lg:w-60' : 'lg:w-24',
      ]"
    >
      <div
        class="flex items-center gap-2 pb-4 pt-1"
        :class="sidebarVisible ? 'justify-between px-3' : 'justify-center gap-1'"
      >
        <RouterLink :to="{ name: 'home' }" class="flex min-w-0 items-center gap-2 text-xl font-bold">
          <img
            src="/logo-pasarpintar-transparent.png"
            alt=""
            class="shrink-0 object-contain"
            :class="sidebarVisible ? 'h-9 w-9' : 'h-8 w-8'"
          />
          <span v-if="sidebarVisible" class="truncate">PasarPintar</span>
        </RouterLink>
        <button
          v-if="sidebarExpanded || mobileSidebarOpen"
          class="inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-lg text-slate-600 hover:bg-white hover:text-slate-900"
          type="button"
          :aria-label="mobileSidebarOpen ? 'Tutup menu' : 'Ciutkan sidebar'"
          :title="mobileSidebarOpen ? 'Tutup menu' : 'Ciutkan sidebar'"
          @click="mobileSidebarOpen ? (mobileSidebarOpen = false) : (sidebarExpanded = !sidebarExpanded)"
        >
          <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <path :d="sidebarExpanded ? 'M15 18l-6-6 6-6' : 'M9 18l6-6-6-6'" />
            <path d="M4 5v14" />
          </svg>
        </button>
      </div>
      <p v-if="sidebarVisible" class="px-3 pb-1.5 pt-3 text-xs text-muted">Menu Utama</p>
      <template v-for="item in visibleMenu" :key="item.label">
        <div v-if="item.separator" class="mx-3 my-2 border-t border-slate-200" aria-hidden="true"></div>
        <RouterLink
          v-if="item.to"
          :to="item.to"
          class="flex items-center gap-2.5 rounded-[10px] px-3 py-2.5 text-sm text-[#4B5563]"
          :class="{ 'lg:justify-center': !sidebarVisible }"
          :title="!sidebarVisible ? item.label : undefined"
          :aria-label="!sidebarVisible ? item.label : undefined"
          active-class="!bg-white !font-semibold !text-gray-900 shadow-sm"
          @click="mobileSidebarOpen = false"
        >
          <svg class="h-[18px] w-[18px]" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path :d="item.icon" /></svg>
          <span v-if="sidebarVisible">{{ item.label }}</span>
        </RouterLink>
        <span
          v-else
          class="flex cursor-not-allowed items-center gap-2.5 rounded-[10px] px-3 py-2.5 text-sm text-muted opacity-70"
          :class="{ 'lg:justify-center': !sidebarVisible }"
          :title="!sidebarVisible ? item.label : undefined"
          :aria-label="!sidebarVisible ? item.label : undefined"
          aria-disabled="true"
        >
          <svg class="h-[18px] w-[18px]" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path :d="item.icon" /></svg>
          <span v-if="sidebarVisible">{{ item.label }}</span>
          <span v-if="sidebarVisible" class="ml-auto text-xs">Segera</span>
        </span>
      </template>
    </aside>

    <div class="flex min-w-0 flex-1 flex-col">
      <header class="flex items-center justify-between gap-3 px-4 py-4 md:px-6 lg:px-8">
        <div class="flex items-center gap-3">
          <button
            class="inline-flex h-9 w-9 items-center justify-center rounded-lg border border-slate-200 text-slate-700 hover:bg-white lg:hidden"
            type="button"
            :aria-label="mobileSidebarOpen ? 'Tutup menu' : 'Buka menu'"
            :aria-expanded="mobileSidebarOpen"
            @click="mobileSidebarOpen = !mobileSidebarOpen"
          >
            <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true">
              <path d="M4 6h16M4 12h16M4 18h16" />
            </svg>
          </button>
          <RouterLink :to="{ name: 'home' }" class="text-sm font-semibold lg:invisible">← Lihat toko</RouterLink>
        </div>
        <div class="flex items-center gap-3">
          <div class="relative">
            <button
              class="relative inline-flex h-10 w-10 items-center justify-center rounded-xl border border-slate-200 bg-white text-slate-700 hover:bg-slate-50"
              type="button"
              aria-label="Notifikasi pembayaran"
              :aria-expanded="notificationsOpen"
              @click="notificationsOpen = !notificationsOpen; loadPaymentNotifications()"
            >
              <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4" />
              </svg>
              <span
                v-if="unreadNotificationCount"
                class="absolute -right-1 -top-1 inline-flex min-h-5 min-w-5 items-center justify-center rounded-full bg-red-600 px-1 text-[10px] font-bold text-white"
                aria-hidden="true"
              >{{ unreadNotificationCount > 99 ? '99+' : unreadNotificationCount }}</span>
            </button>
            <section
              v-if="notificationsOpen"
              class="absolute right-0 z-50 mt-2 w-[min(22rem,calc(100vw-2rem))] overflow-hidden rounded-xl border border-slate-200 bg-white shadow-xl"
              aria-label="Notifikasi pembayaran masuk"
            >
              <div class="border-b border-slate-100 px-4 py-3">
                <h2 class="font-semibold text-slate-900">Pembayaran terkonfirmasi</h2>
                <p class="mt-1 text-xs text-slate-500">Pembaruan otomatis setiap 30 detik. COD tidak ditampilkan.</p>
              </div>
              <p v-if="notificationError" class="p-4 text-sm text-red-700" role="alert">{{ notificationError }}</p>
              <p v-else-if="!notifications.length" class="p-4 text-sm text-slate-500">Belum ada pembayaran terkonfirmasi.</p>
              <div v-else class="max-h-96 divide-y divide-slate-100 overflow-y-auto">
                <button
                  v-for="notification in notifications"
                  :key="notification.id"
                  class="block w-full px-4 py-3 text-left hover:bg-slate-50"
                  :class="notification.is_read ? 'bg-white' : 'bg-emerald-50/70'"
                  type="button"
                  @click="openPaymentNotification(notification)"
                >
                  <span class="flex items-start justify-between gap-3">
                    <span class="font-semibold text-slate-900">Pesanan {{ notification.order_no }}</span>
                    <span v-if="!notification.is_read" class="mt-1 h-2 w-2 shrink-0 rounded-full bg-emerald-600" aria-label="Belum dibaca" />
                  </span>
                  <span class="mt-1 block text-sm font-medium text-emerald-800">{{ formatRupiah(notification.amount) }}</span>
                  <span class="mt-1 block text-xs text-slate-500">{{ notification.payment_method }} · {{ formatTanggalJam(notification.paid_at) }}</span>
                </button>
              </div>
              <p class="border-t border-slate-100 px-4 py-2 text-[11px] text-slate-500">Status ini adalah pencatatan pembayaran, bukan bukti transfer uang oleh aplikasi.</p>
            </section>
          </div>
          <div class="card px-3.5 py-2 text-sm">
            <p class="font-semibold leading-tight">{{ auth.profile?.full_name || 'Admin' }}</p>
            <p class="text-xs text-muted">{{ auth.isSuperAdmin ? 'Super Admin' : 'Admin' }}</p>
          </div>
          <button class="btn-outline" type="button" @click="keluar">Keluar</button>
        </div>
      </header>
      <main class="flex-1 px-4 pb-10 md:px-6 lg:px-8"><RouterView /></main>
    </div>
  </div>
</template>
