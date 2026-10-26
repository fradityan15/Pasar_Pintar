import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const StoreLayout = () => import('@/layouts/StoreLayout.vue')
const AuthLayout = () => import('@/layouts/AuthLayout.vue')
const AdminLayout = () => import('@/layouts/AdminLayout.vue')

const routes = [
  {
    path: '/',
    component: StoreLayout,
    children: [
      { path: '', name: 'home', component: () => import('@/pages/store/HomePage.vue'), meta: { title: 'Beranda' } },
      { path: 'katalog', name: 'katalog', component: () => import('@/pages/store/CatalogPage.vue'), meta: { title: 'Katalog' } },
      { path: 'akun', name: 'akun', component: () => import('@/pages/store/AccountPage.vue'), meta: { title: 'Akun saya', requiresAuth: true } },
      { path: 'umkm', name: 'umkm', component: () => import('@/pages/store/UmkmListPage.vue'), meta: { title: 'UMKM mitra' } },
      { path: 'umkm/:slug', name: 'umkm-detail', component: () => import('@/pages/store/UmkmDetailPage.vue'), meta: { title: 'Profil UMKM' } },
      { path: 'mitra/produk', name: 'umkm-products', component: () => import('@/pages/store/UmkmProductsPage.vue'), meta: { title: 'Dasbor UMKM', requiresAuth: true } },
      { path: 'mitra/pesanan', name: 'umkm-orders', component: () => import('@/pages/store/UmkmOrdersPage.vue'), meta: { title: 'Pesanan masuk', requiresAuth: true } },
      { path: 'mitra/pengaturan', name: 'umkm-settings', component: () => import('@/pages/store/UmkmSettingsPage.vue'), meta: { title: 'Pengaturan Toko', requiresAuth: true } },
      { path: 'produk/:slug', name: 'produk', component: () => import('@/pages/store/ProductDetailPage.vue'), meta: { title: 'Detail produk' } },
      { path: 'keranjang', alias: '/cart', name: 'keranjang', component: () => import('@/pages/store/CartPage.vue'), meta: { title: 'Keranjang' } },
      { path: 'checkout', name: 'checkout', component: () => import('@/pages/store/CheckoutPage.vue'), meta: { title: 'Checkout', requiresAuth: true } },
      { path: 'payment-simulation/:orderId', name: 'payment-simulation', component: () => import('@/pages/store/MockPaymentPage.vue'), meta: { title: 'Pembayaran', requiresAuth: true } },
      { path: 'pesanan', name: 'pesanan', component: () => import('@/pages/store/OrdersPage.vue'), meta: { title: 'Pesanan saya', requiresAuth: true } },
      { path: 'pesanan/:id', name: 'pesanan-detail', component: () => import('@/pages/store/OrderDetailPage.vue'), meta: { title: 'Detail pesanan', requiresAuth: true } },
    ],
  },
  {
    path: '/',
    component: AuthLayout,
    meta: { guestOnly: true },
    children: [
      { path: 'masuk', name: 'login', component: () => import('@/pages/auth/LoginPage.vue'), meta: { title: 'Masuk' } },
      { path: 'daftar', name: 'register', component: () => import('@/pages/auth/RegisterPage.vue'), meta: { title: 'Daftar' } },
    ],
  },
  {
    path: '/admin',
    component: AdminLayout,
    meta: { requiresAuth: true, requiresAdmin: true },
    children: [
      { path: '', redirect: { name: 'admin-dashboard' } },
      { path: 'ringkasan', name: 'admin-dashboard', component: () => import('@/pages/admin/DashboardPage.vue'), meta: { title: 'Ringkasan' } },
      { path: 'pesanan', name: 'admin-pesanan', component: () => import('@/pages/admin/AdminOrdersPage.vue'), meta: { title: 'Pesanan' } },
      { path: 'pesanan/:id', name: 'admin-pesanan-detail', component: () => import('@/pages/admin/AdminOrderDetailPage.vue'), meta: { title: 'Detail pesanan' } },
      { path: 'produk', name: 'admin-produk', component: () => import('@/pages/admin/AdminProductsPage.vue'), meta: { title: 'Produk' } },
      { path: 'produk/baru', name: 'admin-produk-baru', component: () => import('@/pages/admin/AdminProductFormPage.vue'), meta: { title: 'Tambah produk' } },
      { path: 'produk/:id', name: 'admin-produk-edit', component: () => import('@/pages/admin/AdminProductFormPage.vue'), meta: { title: 'Ubah produk' } },
      { path: 'kategori', name: 'admin-kategori', component: () => import('@/pages/admin/AdminCategoriesPage.vue'), meta: { title: 'Kategori' } },
      { path: 'umkm', name: 'admin-umkm', component: () => import('@/pages/admin/AdminUmkmPage.vue'), meta: { title: 'UMKM' } },
      { path: 'keuangan', name: 'admin-keuangan', component: () => import('@/pages/admin/AdminFinancePage.vue'), meta: { title: 'Keuangan' } },
      { path: 'pengguna', name: 'admin-pengguna', component: () => import('@/pages/admin/AdminUsersPage.vue'), meta: { title: 'Pengguna' } },
      { path: 'laporan', name: 'admin-laporan', component: () => import('@/pages/admin/AdminReportsPage.vue'), meta: { title: 'Laporan' } },
      { path: 'konten', name: 'admin-konten', component: () => import('@/pages/admin/AdminContentPage.vue'), meta: { title: 'Manajemen Konten' } },
      { path: 'pengaturan', name: 'admin-pengaturan', component: () => import('@/pages/admin/AdminSettingsPage.vue'), meta: { title: 'Pengaturan' } },
      { path: 'pesanan', name: 'admin-pesanan', component: () => import('@/pages/admin/AdminOrdersPage.vue'), meta: { title: 'Pesanan' } },
      { path: 'pesanan/:id', name: 'admin-pesanan-detail', component: () => import('@/pages/admin/AdminOrderDetailPage.vue'), meta: { title: 'Detail pesanan' } },
      { path: 'produk', name: 'admin-produk', component: () => import('@/pages/admin/AdminProductsPage.vue'), meta: { title: 'Produk' } },
      { path: 'produk/baru', name: 'admin-produk-baru', component: () => import('@/pages/admin/AdminProductFormPage.vue'), meta: { title: 'Tambah produk' } },
      { path: 'produk/:id', name: 'admin-produk-edit', component: () => import('@/pages/admin/AdminProductFormPage.vue'), meta: { title: 'Ubah produk' } },
      { path: 'kategori', name: 'admin-kategori', component: () => import('@/pages/admin/AdminCategoriesPage.vue'), meta: { title: 'Kategori' } },
      { path: 'umkm', name: 'admin-umkm', component: () => import('@/pages/admin/AdminUmkmPage.vue'), meta: { title: 'UMKM' } },
      { path: 'pengguna', name: 'admin-pengguna', component: () => import('@/pages/admin/AdminUsersPage.vue'), meta: { title: 'Pengguna' } },
      { path: 'laporan', name: 'admin-laporan', component: () => import('@/pages/admin/AdminReportsPage.vue'), meta: { title: 'Laporan' } },
    ],
  },
  { path: '/:pathMatch(.*)*', name: 'not-found', component: () => import('@/pages/NotFoundPage.vue'), meta: { title: 'Halaman tidak ditemukan' } },
]

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes,
  scrollBehavior: (to, from, saved) => saved || { top: 0 },
})

router.beforeEach(async (to) => {
  const auth = useAuthStore()
  await auth.init()

  if (to.meta.requiresAuth && !auth.isLoggedIn) {
    return { name: 'login', query: { redirect: to.fullPath } }
  }
  if (to.meta.requiresAdmin && !auth.isAdmin) return { name: 'home' }
  if (to.meta.guestOnly && auth.isLoggedIn) {
    return { name: auth.isAdmin ? 'admin-dashboard' : 'home' }
  }
})

router.afterEach((to) => {
  document.title = to.meta.title ? `${to.meta.title} · PasarPintar` : 'PasarPintar'
})

export default router
