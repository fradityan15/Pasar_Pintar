# Tahap 4C: cara memasang (2 tempelan)

File baru sudah di folder `src/`. Ekstrak zip ke proyek (tidak menimpa file Anda).
Lalu ubah DUA file milik Anda:

## 1. src/router/index.js
Di dalam `children` dari rute `path: '/admin'`, tambahkan setelah rute 'admin-dashboard':

```js
      { path: 'pesanan', name: 'admin-pesanan', component: () => import('@/pages/admin/AdminOrdersPage.vue'), meta: { title: 'Pesanan' } },
      { path: 'pesanan/:id', name: 'admin-pesanan-detail', component: () => import('@/pages/admin/AdminOrderDetailPage.vue'), meta: { title: 'Detail pesanan' } },
      { path: 'produk', name: 'admin-produk', component: () => import('@/pages/admin/AdminProductsPage.vue'), meta: { title: 'Produk' } },
      { path: 'produk/baru', name: 'admin-produk-baru', component: () => import('@/pages/admin/AdminProductFormPage.vue'), meta: { title: 'Tambah produk' } },
      { path: 'produk/:id', name: 'admin-produk-edit', component: () => import('@/pages/admin/AdminProductFormPage.vue'), meta: { title: 'Ubah produk' } },
      { path: 'kategori', name: 'admin-kategori', component: () => import('@/pages/admin/AdminCategoriesPage.vue'), meta: { title: 'Kategori' } },
      { path: 'umkm', name: 'admin-umkm', component: () => import('@/pages/admin/AdminUmkmPage.vue'), meta: { title: 'UMKM' } },
      { path: 'pengguna', name: 'admin-pengguna', component: () => import('@/pages/admin/AdminUsersPage.vue'), meta: { title: 'Pengguna' } },
      { path: 'laporan', name: 'admin-laporan', component: () => import('@/pages/admin/AdminReportsPage.vue'), meta: { title: 'Laporan' } },
```

## 2. src/layouts/AdminLayout.vue
Ganti isi `const menu = [ ... ]` dengan (agar menu bisa diklik):

```js
const menu = [
  { label: 'Ringkasan', to: { name: 'admin-dashboard' }, icon: 'M4 4h7v7H4zM13 4h7v7h-7zM4 13h7v7H4zM13 13h7v7h-7z' },
  { label: 'Pesanan', to: { name: 'admin-pesanan' }, icon: 'M6 3h12v18l-3-2-3 2-3-2-3 2zM9 8h6M9 12h6' },
  { label: 'Produk', to: { name: 'admin-produk' }, icon: 'M3 8l9-5 9 5v8l-9 5-9-5zM3 8l9 5 9-5M12 13v8' },
  { label: 'Kategori', to: { name: 'admin-kategori' }, icon: 'M4 4h7l9 9-7 7-9-9z' },
  { label: 'UMKM', to: { name: 'admin-umkm' }, icon: 'M4 10l1-5h14l1 5M5 10v10h14V10M9 20v-5h6v5' },
  { label: 'Pengguna', to: { name: 'admin-pengguna' }, icon: 'M12 12a4 4 0 100-8 4 4 0 000 8zM4 21c1-4 4-6 8-6s7 2 8 6' },
  { label: 'Laporan', to: { name: 'admin-laporan' }, icon: 'M5 20V10M12 20V4M19 20v-7' },
]
```
Simpan, lalu `npm run dev` (tidak perlu npm install atau SQL baru).
