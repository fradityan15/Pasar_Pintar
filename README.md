# PasarPintar

Platform e-commerce UMKM. Vue 3 + Vite + Tailwind CSS + Pinia + Vue Router + Supabase.

## Menjalankan di komputer

1. Pastikan Node.js 18+ terpasang (`node -v`).
2. Siapkan database: jalankan migrasi secara berurutan `001..003`, `005_umkm_ownership.sql`, `006_umkm_product_images.sql`, `007_seller_orders.sql`, `008_seller_store_settings.sql`, `009_seller_order_tracking.sql`, `010_buyer_order_completion.sql`, `011_order_shipment_completion.sql`, `012_selected_cart_checkout.sql`, `013_checkout_shipping_options.sql`, dan `014_live_dashboard_data.sql`, lalu jalankan `01_setup_payments.sql` dan `seed.sql` di Supabase SQL Editor. `seed.sql` hanya mengisi data referensi kategori/daerah dan membersihkan data demo lama dengan slug yang sudah ditentukan; produk dan UMKM dibuat lewat aplikasi. `004_cron.sql` bersifat opsional dan memerlukan ekstensi pg_cron.
3. Salin `.env.example` menjadi `.env`, isi `VITE_SUPABASE_URL` dan `VITE_SUPABASE_ANON_KEY`.
4. Pasang dan jalankan:
   ```
   npm install
   npm run dev
   ```
   Buka http://localhost:5173

## Menjadikan akun sebagai admin

Daftar lewat halaman /daftar, lalu di Supabase SQL Editor:

```sql
update public.profiles set role = 'admin'
where id = (select id from auth.users where email = 'EMAIL_ANDA');
```

Keluar lalu masuk lagi. Admin diarahkan ke /admin/ringkasan.

## Struktur

```
src/
  lib/         klien Supabase, format Rupiah/tanggal
  services/    semua query Supabase (halaman tidak memanggil Supabase langsung)
  stores/      Pinia (auth)
  router/      rute + guard peran
  layouts/     StoreLayout, AuthLayout, AdminLayout
  pages/       store/, auth/, admin/
  components/  komponen yang dipakai ulang
```

## Deploy

`npm run build` menghasilkan folder `dist`. `vercel.json` dan `public/_redirects` sudah menangani refresh pada rute SPA.
Isi dua environment variable di atas di dashboard Vercel/Netlify.

## Alur belanja (Tahap 4B)

Detail produk `/produk/:slug` → keranjang `/keranjang` → checkout `/checkout` → pesanan `/pesanan/:id`.
Checkout memanggil fungsi database `create_order` (stok dikunci dan dikurangi dalam satu transaksi). Setelah migrasi `012_selected_cart_checkout.sql`, pembeli dapat memilih item keranjang; hanya item terpilih yang menjadi pesanan, sementara item lain tetap di keranjang. Migrasi `013_checkout_shipping_options.sql` menyimpan metode dan ongkir pada pesanan. Tarif pengiriman standar platform saat ini Rp 15.000; samakan nilai `FLAT_SHIPPING` di `src/lib/status.js` dengan tarif dalam fungsi database.
Jalankan `02_seed_payment_methods.sql` di Supabase SQL Editor untuk menambahkan COD dan rekening transfer awal (skrip aman dijalankan ulang). Tambahkan QRIS hanya setelah URL gambar QR merchant resmi tersedia. Baris nonaktif tidak dibaca publik dan metode yang sudah dipakai pesanan tidak dapat dihapus.
Pesanan baru dicatat dengan status menunggu pembayaran. Konfirmasi pembayaran tidak disimulasikan; integrasikan payment gateway dan webhook untuk mengubah status setelah pembayaran benar-benar terverifikasi. Migrasi `014_live_dashboard_data.sql` menghapus RPC uji bayar dan menyediakan agregasi dashboard berdasarkan transaksi nyata.

## Pendaftaran mitra UMKM

Pengguna mengajukan pendaftaran dari halaman Akun. Admin menyetujui pendaftaran di menu UMKM;
setelah status aktif, pemilik dapat mengelola produk tokonya melalui Dasbor UMKM.
Alur ini memerlukan migrasi `005_umkm_ownership.sql` dan `006_umkm_product_images.sql` untuk izin foto produk milik penjual. Pesanan masuk penjual tersedia pada `/mitra/pesanan` setelah migrasi `007_seller_orders.sql`; status pengiriman disimpan per item/toko agar pesanan multi-UMKM tidak mengubah status toko lain. Migrasi `011_order_shipment_completion.sql` memperbarui status pesanan global menjadi dikirim setelah semua mitra dalam pesanan menyelesaikan pengiriman. Pengaturan Toko tersedia pada `/mitra/pengaturan` setelah migrasi `008_seller_store_settings.sql`; data rekening hanya dibaca dan diubah melalui RPC yang memverifikasi pemilik UMKM aktif. Pelacakan status penjual memakai RPC aman di `009_seller_order_tracking.sql`; pembeli/admin membaca log sesuai kebijakan RLS. Pembeli dapat mengonfirmasi penerimaan pesanan setelah migrasi `010_buyer_order_completion.sql`.
