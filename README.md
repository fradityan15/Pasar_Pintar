# PasarPintar

Platform e-commerce UMKM. Vue 3 + Vite + Tailwind CSS + Pinia + Vue Router + Supabase.

## Menjalankan di komputer

1. Pastikan Node.js 18+ terpasang (`node -v`).
2. Siapkan database di Supabase SQL Editor dengan urutan:
   - Migrasi `001_schema.sql` sampai `003_functions.sql`.
   - Migrasi `005_umkm_ownership.sql` sampai `014_live_dashboard_data.sql` secara berurutan. `004_cron.sql` opsional dan memerlukan ekstensi pg_cron.
   - Jalankan `01_setup_payments.sql`, lalu migrasi `015_checkout_payment_options.sql` sampai `027_admin_global_analytics.sql` secara berurutan.
   - Jalankan `02_seed_payment_methods.sql` dan `supabase/seed.sql`.

   Jalankan setiap file migrasi secara berurutan. Khususnya, pastikan `025_order_waiting_for_seller.sql` selesai sebelum menjalankan `026_order_role_separation.sql`, karena migrasi 026 memakai nilai enum baru yang ditambahkan pada migrasi 025.
   Migrasi `027_admin_global_analytics.sql` menambahkan RPC khusus admin untuk menghitung metrik global dashboard, tren transaksi 30 hari, dan leaderboard UMKM.
   `seed.sql` hanya mengisi data referensi kategori/daerah dan membersihkan data demo lama dengan slug yang sudah ditentukan; produk dan UMKM dibuat lewat aplikasi. Database yang sudah memakai migrasi lama cukup menjalankan migrasi yang belum diterapkan sesuai nomor urutnya.
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
Pembayaran transfer diverifikasi secara manual oleh admin setelah dana benar-benar terlihat di rekening; aplikasi ini belum terhubung ke payment gateway/webhook. Tombol pembeli hanya memuat status terbaru dan tidak dapat mengubah pesanan menjadi dibayar. Admin mengonfirmasi transfer dari halaman detail pesanan setelah memeriksa mutasi bank; referensi transaksi dicatat di log status. Data rekening yang dimasukkan oleh `02_seed_payment_methods.sql` adalah data awal/demo dan wajib diganti dengan rekening merchant resmi sebelum digunakan. COD diproses penjual sebagai COD dan dicatat dibayar setelah pembeli mengonfirmasi penerimaan.
Setelah migrasi `025_order_waiting_for_seller.sql` dan `026_order_role_separation.sql`, admin hanya memverifikasi pembayaran transfer. Pesanan yang terbayar menunggu penjual (`menunggu_diproses`), lalu penjual menerima/memproses dan mengirim pesanan melalui RPC khusus yang memeriksa UMKM pemilik. COD langsung tersedia bagi penjual dan tetap dibayar saat barang diterima.

## Pendaftaran mitra UMKM

Pengguna mengajukan pendaftaran dari halaman Akun. Admin menyetujui pendaftaran di menu UMKM;
setelah status aktif, pemilik dapat mengelola produk tokonya melalui Dasbor UMKM.
Alur ini memerlukan migrasi `005_umkm_ownership.sql` dan `006_umkm_product_images.sql` untuk izin foto produk milik penjual. Pesanan masuk penjual tersedia pada `/mitra/pesanan` setelah migrasi `007_seller_orders.sql`; status pengiriman disimpan per item/toko agar pesanan multi-UMKM tidak mengubah status toko lain. Migrasi `011_order_shipment_completion.sql` memperbarui status pesanan global menjadi dikirim setelah semua mitra dalam pesanan menyelesaikan pengiriman. Pengaturan Toko tersedia pada `/mitra/pengaturan` setelah migrasi `008_seller_store_settings.sql`; data rekening hanya dibaca dan diubah melalui RPC yang memverifikasi pemilik UMKM aktif. Pelacakan status penjual memakai RPC aman di `009_seller_order_tracking.sql`; pembeli/admin membaca log sesuai kebijakan RLS. Pembeli dapat mengonfirmasi penerimaan pesanan setelah migrasi `010_buyer_order_completion.sql`.
