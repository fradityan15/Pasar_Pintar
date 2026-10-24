# Tahap 4D: cara memasang

Syarat: paket 4C sudah terpasang (halaman Akun memakai ModalDialog dari 4C).
Ekstrak zip ke proyek, lalu ubah dua file milik Anda.

## 1. src/router/index.js
Di dalam `children` rute toko (yang berisi 'home' dan 'katalog'), tambahkan:

```js
      { path: 'akun', name: 'akun', component: () => import('@/pages/store/AccountPage.vue'), meta: { title: 'Akun saya', requiresAuth: true } },
      { path: 'umkm', name: 'umkm', component: () => import('@/pages/store/UmkmListPage.vue'), meta: { title: 'UMKM mitra' } },
      { path: 'umkm/:slug', name: 'umkm-detail', component: () => import('@/pages/store/UmkmDetailPage.vue'), meta: { title: 'Profil UMKM' } },
```

## 2. src/layouts/StoreLayout.vue
Di `<nav aria-label="Menu utama">`, setelah link Katalog, tambahkan:

```vue
<RouterLink :to="{ name: 'umkm' }" active-class="border-b-2 border-ink" class="py-2">UMKM</RouterLink>
```

Di blok pengguna login (dekat link "Pesanan"), tambahkan:

```vue
<RouterLink :to="{ name: 'akun' }" class="btn-outline hidden sm:inline-flex">Akun</RouterLink>
```

Opsional: di ProductDetailPage, tautkan nama UMKM ke `{ name: 'umkm-detail', params: { slug } }`
(tambahkan `slug` pada select `umkm(...)` di getProductBySlug).

## 3. Database (opsional tapi disarankan)
Aktifkan pg_cron lalu jalankan `supabase/migrations/004_cron.sql`.
