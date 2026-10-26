<script setup>
import { ref } from 'vue'
import { RouterLink } from 'vue-router'

defineProps({
  umkm: { type: Object, default: null },
  active: { type: String, required: true },
})

const mobileMenuOpen = ref(false)

const linkClass = (isActive) => [
  'flex shrink-0 items-center gap-3 rounded-lg px-3 py-2.5 text-sm transition lg:w-full',
  isActive
    ? 'bg-emerald-50 font-semibold text-emerald-800 ring-1 ring-inset ring-emerald-100'
    : 'font-medium text-slate-600 hover:bg-slate-100 hover:text-slate-900',
]
</script>

<template>
  <aside class="sticky top-0 z-20 w-full shrink-0 self-start bg-white lg:h-screen lg:w-64 lg:overflow-y-auto lg:border-r lg:border-slate-200">
    <div class="flex items-center justify-between border-b border-slate-100 px-5 py-4 lg:block lg:py-5">
      <RouterLink :to="{ name: 'akun' }" class="hidden text-xs font-medium text-slate-500 hover:text-slate-900 lg:inline-block">← Kembali ke akun</RouterLink>
      <div class="mt-4 flex items-center gap-3">
        <img src="/logo-pasarpintar-transparent.png" alt="" class="h-10 w-10 shrink-0 object-contain" />
        <div class="min-w-0">
          <p class="truncate text-sm font-semibold text-slate-900">{{ umkm?.name || 'Toko Anda' }}</p>
          <p class="mt-0.5 text-xs text-slate-500">Dasbor penjual</p>
        </div>
      </div>
      <button
        class="inline-flex h-10 w-10 shrink-0 items-center justify-center rounded-lg border border-slate-200 text-slate-700 hover:bg-slate-50 lg:hidden"
        type="button"
        :aria-expanded="mobileMenuOpen"
        aria-controls="seller-mobile-navigation"
        :aria-label="mobileMenuOpen ? 'Tutup menu' : 'Buka menu'"
        @click="mobileMenuOpen = !mobileMenuOpen"
      >
        <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true">
          <path v-if="mobileMenuOpen" d="m6 6 12 12M18 6 6 18" />
          <path v-else d="M4 6h16M4 12h16M4 18h16" />
        </svg>
      </button>
    </div>

    <button
      v-if="mobileMenuOpen"
      class="fixed inset-0 z-30 bg-black/30 lg:hidden"
      type="button"
      aria-label="Tutup menu"
      @click="mobileMenuOpen = false"
    ></button>

    <nav
      id="seller-mobile-navigation"
      class="gap-1 p-3 lg:flex lg:flex-col"
      :class="mobileMenuOpen ? 'fixed inset-y-0 left-0 z-40 flex w-72 flex-col overflow-y-auto bg-white shadow-xl lg:static lg:w-full lg:overflow-visible lg:shadow-none' : 'hidden lg:flex'"
      aria-label="Navigasi dasbor penjual"
    >
      <div class="mb-2 flex items-center justify-between border-b border-slate-100 px-3 pb-3 pt-1 lg:hidden">
        <span class="text-sm font-semibold text-slate-900">Menu penjual</span>
        <button class="rounded-lg p-2 text-slate-600 hover:bg-slate-100" type="button" aria-label="Tutup menu" @click="mobileMenuOpen = false">
          <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true">
            <path d="m6 6 12 12M18 6 6 18" />
          </svg>
        </button>
      </div>
      <RouterLink :to="{ name: 'umkm-products', hash: '#ringkasan' }" :class="linkClass(active === 'overview')" @click="mobileMenuOpen = false">
        <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
          <rect x="3" y="3" width="8" height="8" rx="1.5" /><rect x="13" y="3" width="8" height="5" rx="1.5" />
          <rect x="13" y="10" width="8" height="11" rx="1.5" /><rect x="3" y="13" width="8" height="8" rx="1.5" />
        </svg>
        Ringkasan
      </RouterLink>
      <RouterLink :to="{ name: 'umkm-products', hash: '#produk-saya' }" :class="linkClass(active === 'products')" :aria-current="active === 'products' ? 'page' : undefined" @click="mobileMenuOpen = false">
        <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
          <path stroke-linecap="round" stroke-linejoin="round" d="m3 7 9-4 9 4-9 4-9-4Zm0 0v10l9 4 9-4V7M12 11v10" />
        </svg>
        Produk Saya
      </RouterLink>
      <RouterLink :to="{ name: 'umkm-orders' }" :class="linkClass(active === 'orders')" :aria-current="active === 'orders' ? 'page' : undefined" @click="mobileMenuOpen = false">
        <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
          <path stroke-linecap="round" stroke-linejoin="round" d="M5 8h14l1 12H4L5 8Zm4 0a3 3 0 0 1 6 0M8 12h.01M16 12h.01" />
        </svg>
        Pesanan
      </RouterLink>
      <RouterLink :to="{ name: 'umkm-settings' }" :class="linkClass(active === 'settings')" :aria-current="active === 'settings' ? 'page' : undefined" @click="mobileMenuOpen = false">
        <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
          <circle cx="12" cy="12" r="3" /><path stroke-linecap="round" stroke-linejoin="round" d="m19.4 15 .1.1a1.7 1.7 0 1 1-2.4 2.4L17 17.4a1.7 1.7 0 0 0-2.9 1.2v.2a1.7 1.7 0 1 1-3.4 0v-.2a1.7 1.7 0 0 0-2.9-1.2l-.1.1a1.7 1.7 0 1 1-2.4-2.4l.1-.1a1.7 1.7 0 0 0-1.2-2.9H4a1.7 1.7 0 1 1 0-3.4h.2a1.7 1.7 0 0 0 1.2-2.9l-.1-.1a1.7 1.7 0 1 1 2.4-2.4l.1.1a1.7 1.7 0 0 0 2.9-1.2V2a1.7 1.7 0 1 1 3.4 0v.2a1.7 1.7 0 0 0 2.9 1.2l.1-.1a1.7 1.7 0 1 1 2.4 2.4l-.1.1a1.7 1.7 0 0 0 1.2 2.9h.2a1.7 1.7 0 1 1 0 3.4h-.2a1.7 1.7 0 0 0-1.2 2.9Z" />
        </svg>
        Pengaturan Toko
      </RouterLink>
    </nav>
  </aside>
</template>
