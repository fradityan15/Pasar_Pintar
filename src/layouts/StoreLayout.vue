<script setup>
import { computed, ref, watch } from 'vue'
import { RouterLink, RouterView, useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useCartStore } from '@/stores/cart'
import { getMyUmkm } from '@/services/umkmPartnerService'

const auth = useAuthStore()
const cart = useCartStore()
const router = useRouter()
const search = ref('')
const myUmkm = ref(null)
const umkmCheckError = ref('')
let umkmCheckRequest = 0
const firstName = computed(() => auth.profile?.full_name?.trim().split(/\s+/)[0] || 'Pengguna')
const initials = computed(() =>
  (auth.profile?.full_name || auth.user?.email || 'P')
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() || '')
    .join(''),
)
const avatarUrl = computed(() => auth.user?.user_metadata?.avatar_url || auth.user?.user_metadata?.picture || '')

watch(
  () => auth.user?.id,
  async (userId) => {
    const requestId = ++umkmCheckRequest
    myUmkm.value = null
    umkmCheckError.value = ''
    if (!userId) return
    try {
      const application = await getMyUmkm()
      if (requestId === umkmCheckRequest) myUmkm.value = application
    } catch (error) {
      if (requestId === umkmCheckRequest) umkmCheckError.value = error.message
    }
  },
  { immediate: true },
)

watch(
  () => router.currentRoute.value.query.q,
  (query) => { search.value = String(query ?? '') },
  { immediate: true },
)

async function keluar() {
  await auth.signOut()
  router.push({ name: 'home' })
}

function cari() {
  const q = search.value.trim()
  router.push({ name: 'katalog', query: q ? { q } : {} })
}
</script>

<template>
  <div class="flex min-h-screen flex-col">
    <div class="bg-ink px-4 text-white">
      <div class="mx-auto flex min-h-9 max-w-7xl flex-wrap items-center justify-between gap-x-6 gap-y-1 py-1 text-xs sm:px-10">
        <p class="hidden text-white/80 sm:block">Produk khas daerah, langsung dari UMKM Indonesia</p>
        <div class="flex items-center gap-1">
          <nav class="flex items-center gap-1" aria-label="Menu utama">
            <RouterLink
              :to="{ name: 'home' }"
              exact-active-class="bg-white/15 text-white"
              class="rounded px-3 py-1.5 text-white/80 transition-colors hover:bg-white/10 hover:text-white"
            >Beranda</RouterLink>
            <RouterLink
              :to="{ name: 'katalog' }"
              active-class="bg-white/15 text-white"
              class="rounded px-3 py-1.5 text-white/80 transition-colors hover:bg-white/10 hover:text-white"
            >Katalog</RouterLink>
            <RouterLink
              :to="{ name: 'umkm' }"
              active-class="bg-white/15 text-white"
              class="rounded px-3 py-1.5 text-white/80 transition-colors hover:bg-white/10 hover:text-white"
            >UMKM</RouterLink>
          </nav>
          <div v-if="auth.isLoggedIn" class="group relative ml-1">
            <RouterLink
              :to="{ name: 'akun' }"
              class="flex items-center gap-2 rounded px-2 py-1 text-white/90 transition-colors hover:bg-white/10 hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white"
              aria-haspopup="true"
              aria-label="Menu profil pengguna"
            >
              <span class="flex h-8 w-8 shrink-0 items-center justify-center overflow-hidden rounded-full bg-white/15 text-[11px] font-bold text-white ring-1 ring-white/30">
                <img v-if="avatarUrl" :src="avatarUrl" alt="" class="h-full w-full object-cover" />
                <span v-else>{{ initials }}</span>
              </span>
              <span class="hidden sm:inline">Halo, {{ firstName }}</span>
              <svg viewBox="0 0 20 20" class="h-3 w-3" fill="currentColor" aria-hidden="true">
                <path fill-rule="evenodd" d="M5.22 7.47a.75.75 0 0 1 1.06 0L10 11.19l3.72-3.72a.75.75 0 1 1 1.06 1.06l-4.25 4.25a.75.75 0 0 1-1.06 0L5.22 8.53a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" />
              </svg>
            </RouterLink>
            <div class="invisible absolute right-0 top-full z-50 w-52 translate-y-1 rounded-xl border border-line bg-white p-1.5 text-sm text-ink opacity-0 shadow-lg transition duration-150 group-hover:visible group-hover:translate-y-0 group-hover:opacity-100 group-focus-within:visible group-focus-within:translate-y-0 group-focus-within:opacity-100">
              <RouterLink :to="{ name: 'akun' }" class="flex items-center gap-2.5 rounded-lg px-3 py-2.5 hover:bg-surface focus-visible:bg-surface">
                <svg viewBox="0 0 24 24" class="h-4 w-4 text-muted" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
                  <circle cx="12" cy="8" r="3.5" />
                  <path stroke-linecap="round" stroke-linejoin="round" d="M5 20a7 7 0 0 1 14 0" />
                </svg>
                Akun Saya
              </RouterLink>
              <RouterLink :to="{ name: 'pesanan' }" class="flex items-center gap-2.5 rounded-lg px-3 py-2.5 hover:bg-surface focus-visible:bg-surface">
                <svg viewBox="0 0 24 24" class="h-4 w-4 text-muted" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M5 8h14l1 12H4L5 8ZM9 8a3 3 0 0 1 6 0M8 12h.01M16 12h.01" />
                </svg>
                Pesanan
              </RouterLink>
              <RouterLink
                v-if="myUmkm?.status === 'active' && myUmkm.is_active"
                :to="{ name: 'umkm-products' }"
                class="flex items-center gap-2.5 rounded-lg px-3 py-2.5 hover:bg-surface focus-visible:bg-surface"
              >
                <svg viewBox="0 0 24 24" class="h-4 w-4 text-muted" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M3 10h18l-2 10H5L3 10ZM5 10l2-6h10l2 6M9 20v-5h6v5" />
                </svg>
                Dasbor Penjual
              </RouterLink>
              <p v-if="umkmCheckError" class="px-3 py-2 text-xs text-bad-fg" role="status">
                Status toko belum dapat diperiksa.
              </p>
              <RouterLink v-if="auth.isAdmin" :to="{ name: 'admin-dashboard' }" class="flex items-center gap-2.5 rounded-lg px-3 py-2.5 hover:bg-surface focus-visible:bg-surface">
                <svg viewBox="0 0 24 24" class="h-4 w-4 text-muted" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M4 13h6V4H4v9ZM14 20h6V11h-6v9ZM14 8h6V4h-6v4ZM4 20h6v-3H4v3Z" />
                </svg>
                Panel Admin
              </RouterLink>
              <div class="my-1 border-t border-line"></div>
              <button type="button" class="flex w-full items-center gap-2.5 rounded-lg px-3 py-2.5 text-bad-fg hover:bg-bad-bg focus-visible:bg-bad-bg" @click="keluar">
                <svg viewBox="0 0 24 24" class="h-4 w-4" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M10 17l5-5-5-5M15 12H3m9-8h6a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-6" />
                </svg>
                Keluar
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>

    <header class="border-b border-line">
      <div class="mx-auto flex max-w-7xl flex-wrap items-center gap-4 px-4 py-4 sm:px-10 lg:flex-nowrap">
        <RouterLink :to="{ name: 'home' }" class="flex shrink-0 items-center gap-2 text-xl font-bold">
          <img src="/logo-pasarpintar.png" alt="" class="h-10 w-10 rounded-lg object-cover" />
          PasarPintar
        </RouterLink>

        <form
          class="order-3 flex min-w-0 w-full flex-1 rounded-lg border border-line bg-white p-1 focus-within:border-ink focus-within:ring-2 focus-within:ring-ink/10 lg:order-none lg:mx-6 lg:max-w-3xl"
          role="search"
          @submit.prevent="cari"
        >
          <label for="header-search" class="sr-only">Cari produk</label>
          <input
            id="header-search"
            v-model="search"
            type="search"
            placeholder="Cari produk"
            class="min-w-0 flex-1 rounded-l-md bg-transparent px-3 py-2 text-sm text-ink outline-none placeholder:text-muted/70"
          />
          <button
            type="submit"
            class="inline-flex min-h-10 shrink-0 items-center justify-center gap-2 rounded-md bg-ink px-4 text-sm font-semibold text-white transition-colors hover:bg-black focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ink focus-visible:ring-offset-2"
            aria-label="Cari produk"
          >
            <svg viewBox="0 0 24 24" class="h-4 w-4" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
              <circle cx="11" cy="11" r="7" />
              <path stroke-linecap="round" d="m16 16 4 4" />
            </svg>
            <span>Cari</span>
          </button>
        </form>

        <div class="ml-auto flex shrink-0 items-center gap-6">
          <span
            role="img"
            aria-label="Pesan"
            title="Pesan"
            class="flex h-11 w-11 items-center justify-center rounded-lg text-ink transition-colors hover:bg-surface hover:text-ink/70"
          >
            <svg viewBox="0 0 24 24" class="h-6 w-6" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" d="M4 5.5h16v11H9l-5 3v-14Z" />
              <path stroke-linecap="round" d="M8 10h8M8 13.5h5" />
            </svg>
          </span>
          <span
            role="img"
            aria-label="Notifikasi"
            title="Notifikasi"
            class="flex h-11 w-11 items-center justify-center rounded-lg text-ink transition-colors hover:bg-surface hover:text-ink/70"
          >
            <svg viewBox="0 0 24 24" class="h-6 w-6" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" d="M18 9a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4" />
            </svg>
          </span>
          <RouterLink
            to="/cart"
            class="relative flex h-11 w-11 items-center justify-center rounded-lg text-ink transition-colors hover:bg-surface hover:text-ink/70 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ink"
            aria-label="Keranjang"
          >
            <svg viewBox="0 0 24 24" class="h-6 w-6" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" d="M3 4h2l2.2 11.2a2 2 0 0 0 2 1.6h8.6a2 2 0 0 0 1.9-1.4L22 8H6M10 21h.01M18 21h.01" />
            </svg>
            <span
              v-if="cart.count > 0"
              class="absolute -right-0.5 -top-0.5 flex h-5 min-w-5 items-center justify-center rounded-full bg-red-600 px-1 text-[10px] font-bold text-white ring-2 ring-white"
            >{{ cart.count }}</span>
          </RouterLink>
          <template v-if="!auth.isLoggedIn">
            <RouterLink :to="{ name: 'login' }" class="btn-outline">Masuk</RouterLink>
            <RouterLink :to="{ name: 'register' }" class="btn-primary">Daftar</RouterLink>
          </template>
        </div>
      </div>
    </header>

    <main class="flex-1"><RouterView /></main>

    <footer class="bg-ink text-[#C9CBD1]">
      <div class="mx-auto grid max-w-7xl grid-cols-1 gap-10 px-6 py-12 sm:px-10 md:grid-cols-2 lg:grid-cols-4 lg:gap-8">
        <div>
          <p class="text-2xl font-bold text-white">PasarPintar</p>
          <p class="mt-4 max-w-xs text-sm leading-relaxed text-gray-400">
            Platform e-commerce yang membantu UMKM menjual produk khas daerah secara digital.
          </p>
          <div class="mt-5 flex flex-col gap-2 text-sm text-gray-400">
            <a href="mailto:halo@pasarpintar.id" class="transition-colors duration-200 hover:text-white">Email: halo@pasarpintar.id</a>
            <a href="https://wa.me/6281234567890" class="transition-colors duration-200 hover:text-white">WhatsApp: 0812-3456-7890</a>
          </div>
        </div>
        <div>
          <h2 class="mb-4 font-semibold text-white">Belanja</h2>
          <div class="flex flex-col gap-3 text-sm text-gray-400">
            <RouterLink :to="{ name: 'katalog' }" class="transition-colors duration-200 hover:text-white">Katalog</RouterLink>
            <RouterLink :to="{ name: 'umkm' }" class="transition-colors duration-200 hover:text-white">Kategori UMKM</RouterLink>
            <RouterLink :to="{ name: 'katalog' }" class="transition-colors duration-200 hover:text-white">Promo Terbaru</RouterLink>
            <RouterLink :to="{ name: 'katalog' }" class="transition-colors duration-200 hover:text-white">Produk Populer</RouterLink>
          </div>
        </div>
        <div>
          <h2 class="mb-4 font-semibold text-white">Bantuan &amp; Informasi</h2>
          <div class="flex flex-col gap-3 text-sm text-gray-400">
            <RouterLink :to="{ name: 'home' }" class="transition-colors duration-200 hover:text-white">Tentang Kami</RouterLink>
            <a href="mailto:halo@pasarpintar.id?subject=Pusat%20Bantuan" class="transition-colors duration-200 hover:text-white">Pusat Bantuan (FAQ)</a>
            <a href="mailto:halo@pasarpintar.id?subject=Syarat%20dan%20Ketentuan" class="transition-colors duration-200 hover:text-white">Syarat &amp; Ketentuan</a>
            <a href="mailto:halo@pasarpintar.id?subject=Kebijakan%20Privasi" class="transition-colors duration-200 hover:text-white">Kebijakan Privasi</a>
          </div>
        </div>
        <div>
          <h2 class="mb-4 font-semibold text-white">Ikuti Kami</h2>
          <div class="flex items-center gap-3">
            <span role="img" aria-label="Instagram" title="Instagram" class="flex h-10 w-10 items-center justify-center rounded-full bg-white/10 text-gray-300 transition-colors duration-200 hover:bg-white/20 hover:text-white">
              <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
                <rect x="3" y="3" width="18" height="18" rx="5" />
                <circle cx="12" cy="12" r="4" />
                <circle cx="18" cy="6" r="1" fill="currentColor" stroke="none" />
              </svg>
            </span>
            <span role="img" aria-label="Facebook" title="Facebook" class="flex h-10 w-10 items-center justify-center rounded-full bg-white/10 text-gray-300 transition-colors duration-200 hover:bg-white/20 hover:text-white">
              <svg viewBox="0 0 24 24" class="h-5 w-5" fill="currentColor" aria-hidden="true">
                <path d="M13.4 21v-8.2h2.8l.4-3.2h-3.2v-2c0-.9.3-1.5 1.6-1.5h1.7V3.2c-.3 0-1.3-.1-2.5-.1-2.5 0-4.2 1.5-4.2 4.3v2.2H7.2v3.2H10V21h3.4Z" />
              </svg>
            </span>
            <span role="img" aria-label="TikTok" title="TikTok" class="flex h-10 w-10 items-center justify-center rounded-full bg-white/10 text-gray-300 transition-colors duration-200 hover:bg-white/20 hover:text-white">
              <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <path d="M14 4v10.2a4 4 0 1 1-3-3.9M14 7c1 2 2.8 3.2 5 3.4" />
              </svg>
            </span>
          </div>
        </div>
      </div>
      <div class="border-t border-gray-700">
        <div class="mx-auto flex max-w-7xl flex-col gap-2 px-6 py-5 text-center text-[13px] text-gray-400 sm:px-10 md:flex-row md:items-center md:justify-between md:text-left">
          <span>© 2026 PasarPintar</span>
          <span>Bangga mendukung produk lokal Indonesia.</span>
        </div>
      </div>
    </footer>
  </div>
</template>
