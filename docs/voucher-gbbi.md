# Voucher subsidi GBBI

Fitur ini menyediakan mekanisme klaim, validasi checkout server-side, pembatas kuota atomik, laporan admin, dan pencatatan diskon pada pesanan. Kebijakan resmi GBBI belum tersedia di repository. Voucher tidak otomatis aktif; admin perlu memasukkan konfigurasi yang sudah dikonfirmasi.

## Konfigurasi yang tersedia

Admin mengelola kode, tipe diskon (`nominal` atau `persen`), nilai diskon, maksimum potongan opsional, minimum belanja, kuota total opsional, periode berlaku, status aktif, serta cakupan semua toko/toko tertentu/kategori tertentu. Kolom `quota_total = NULL` berarti kuota tanpa batas; status voucher baru dibuat nonaktif.

## Asumsi implementasi yang perlu dikonfirmasi

- Diskon diterapkan ke subtotal produk yang memenuhi cakupan; ongkir tidak didiskon.
- Minimum belanja dihitung dari subtotal produk yang memenuhi cakupan, bukan keseluruhan keranjang.
- Persentase dihitung dari subtotal eligible dan dibulatkan ke rupiah terdekat; `maximum_discount` membatasi potongan persentase. Potongan nominal dibatasi agar tidak melebihi subtotal eligible.
- Waktu berlaku menggunakan timestamp; awal periode inklusif dan akhir periode eksklusif (`berlaku_dari <= now() < berlaku_sampai`).
- Kuota dicadangkan saat pelanggan mengklaim kode, bukan saat checkout. Klaim berstatus `claimed` tanpa order tetap menahan kuota hingga periode voucher berakhir, lalu job mengubahnya menjadi `expired`. Klaim yang sudah terpasang ke order berstatus `used`; pembatalan order atau pembayaran kedaluwarsa mengembalikan satu kuota.
- Aturan `unique(voucher_id, user_id)` berarti satu akun hanya dapat mengklaim satu kali sepanjang masa untuk satu voucher, termasuk setelah klaim kedaluwarsa.
- Diskon mengurangi total yang ditagihkan dan juga mengurangi nilai escrow seller secara proporsional pada item yang memenuhi cakupan. Belum ada ledger sumber dana subsidi/rekonsiliasi penggantian dana GBBI; ini bukan representasi pendanaan resmi.
- Cakupan kategori disimpan sebagai snapshot `order_items.category_id` saat checkout agar perubahan kategori produk setelah transaksi tidak mengubah perhitungan diskon atau escrow.

Mohon konfirmasi terutama: sumber pendanaan/pihak penanggung subsidi, cakupan ke ongkir, dasar minimum belanja, aturan pembulatan dan maksimum potongan, jumlah klaim per akun, kuota reservasi dan masa klaim, waktu/zonawaktu, kelayakan toko/kategori, penggunaan lintas pesanan, serta apakah diskon seller harus direimburse secara terpisah.

## Perlindungan dan konsistensi

- `claim_voucher` mengunci row voucher dengan `FOR UPDATE`, memeriksa status/periode/kuota, lalu menaikkan `quota_used` dan membuat klaim dalam transaksi yang sama. Klaim berulang untuk kode yang sama oleh akun yang sama tidak menggandakan kuota.
- RPC `create_order` enam-parameter memeriksa lagi kepemilikan klaim, status voucher, masa berlaku, scope dan minimum belanja. Jumlah diskon ditentukan di database dan `orders.total` menjadi subtotal + ongkir - diskon.
- Signature lama `create_order` tanpa claim dicabut dari `authenticated` agar tidak ada jalur checkout yang melewati validasi kupon. Caller harus diperbarui ke frontend yang mengirim argumen `p_voucher_claim_id` (boleh `NULL`).
- Trigger pada perubahan order mengubah klaim terpakai menjadi expired dan mengembalikan kuota jika order dibatalkan atau pembayaran kedaluwarsa. Job `expire_unattached_voucher_claims` membersihkan klaim yang belum menjadi order setelah voucher kedaluwarsa.
- `vouchers` memiliki RLS: pengguna terautentikasi hanya dapat membaca voucher aktif, dalam periode, dan masih berkuota; hanya admin dapat melakukan CRUD. `voucher_claims` hanya dapat dibaca pemilik atau admin, tidak dapat ditulis langsung oleh klien.
- Laporan penggunaan menampilkan maksimal 500 klaim terbaru. Seluruh daftar voucher admin tidak dibatasi; untuk dataset besar, tambahkan pagination sebelum penggunaan skala besar.

## Uji staging

Jangan jalankan migration di produksi. Terapkan `033_gbbi_vouchers.sql` ke staging setelah review, lalu jalankan `npm run build`. Pastikan job `expire-unattached-voucher-claims` ada bila ekstensi `pg_cron` aktif. Tanpa `pg_cron`, klaim tanpa order yang lewat masa berlaku baru mengembalikan kuota saat RPC cleanup dijalankan oleh operator yang berwenang.

Semua test berikut menggunakan akun, voucher, dan order staging; buat fixture tersendiri dan jangan memakai data pelanggan nyata.

1. **Kuota habis:** buat voucher aktif dengan `quota_total = 1`, klaim dari satu pengguna, pastikan `quota_used = 1`; klaim dari pengguna berbeda harus gagal dengan pesan kuota habis.
2. **Kedaluwarsa:** buat voucher dengan `berlaku_sampai` di masa lalu; klaim baru harus ditolak. Untuk klaim tanpa order yang telah kedaluwarsa, panggil cleanup sebagai service role di staging dan pastikan status menjadi `expired` serta kuota turun satu kali.
3. **Klaim ganda:** klaim kode yang sama dua kali dengan akun yang sama; klaim kedua harus mengembalikan klaim yang sama dan `quota_used` tidak berubah. Klaim lama yang sudah dipakai/dikedaluwarsakan tidak boleh dibuat ulang untuk akun tersebut.
4. **Minimum belanja:** klaim voucher yang memiliki `minimum_purchase` di atas subtotal eligible; checkout harus gagal dari RPC dan tidak boleh membuat order, mengurangi stok, atau mengubah klaim menjadi used.
5. **Cakupan toko/kategori:** masukkan barang eligible dan non-eligible ke keranjang; hanya subtotal eligible yang digunakan untuk memenuhi minimum dan menghitung diskon.
6. **Diskon transaksi:** checkout sukses dengan klaim; verifikasi `orders.discount_amount`, `voucher_id`, dan `total = subtotal + shipping_cost - discount_amount`, serta klaim `used` dengan `order_id` pesanan.
7. **Pembatalan/kedaluwarsa order:** batalkan order yang memakai voucher atau biarkan order pembayaran melewati expiry lalu jalankan job expiry. Pastikan claim menjadi expired dan kuota berkurang tepat satu kali.
8. **Dua klaim serentak pada kuota terakhir:** gunakan dua sesi pengguna staging berbeda dan panggil `claim_voucher` bersamaan untuk voucher dengan kuota satu. Tepat satu klaim yang berhasil; pastikan `quota_used = 1` dan tidak pernah melebihi `quota_total`.
9. **RLS:** sebagai customer, pastikan hanya voucher aktif yang dapat dibaca, klaim pengguna lain tidak terlihat, serta INSERT/UPDATE/DELETE langsung pada voucher/claim ditolak. Sebagai admin, pastikan CRUD dan laporan klaim dapat dibuka.

Contoh pemeriksaan setelah uji pada SQL Editor staging:

```sql
select code, quota_total, quota_used, is_active, berlaku_dari, berlaku_sampai
from public.vouchers
where code = 'KODE_UJI';

select voucher_id, user_id, order_id, status, claimed_at, used_at
from public.voucher_claims
where voucher_id = (select id from public.vouchers where code = 'KODE_UJI')
order by claimed_at desc;

select id, voucher_id, subtotal, shipping_cost, discount_amount, total, status, payment_status
from public.orders
where voucher_id = (select id from public.vouchers where code = 'KODE_UJI');
```
