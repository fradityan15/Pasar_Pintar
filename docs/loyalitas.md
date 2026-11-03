# Poin loyalitas

Fitur poin memakai `loyalty_ledger` sebagai buku append-only. Saldo adalah agregat `SUM(points)`; entri perolehan bernilai positif, sedangkan penukaran dan kedaluwarsa bernilai negatif. Entri `reverse` membalik dampak perolehan dan penukaran pada pesanan yang dibatalkan/refund. Pengguna hanya dapat membaca ledger miliknya; perubahan hanya melalui RPC/trigger database.

## Default konfigurasi yang perlu disetujui

Migration `034_loyalty_points.sql` mengisi satu baris konfigurasi awal dengan asumsi:

- Setiap Rp10.000 belanja produk bersih menghasilkan 1 poin (pembulatan ke bawah per pesanan).
- Poin dihitung setelah pesanan berstatus selesai dan pembayarannya berstatus dibayar.
- Dasar perolehan adalah subtotal produk dikurangi diskon voucher dan diskon poin; ongkir tidak menghasilkan poin.
- 1 poin bernilai Rp100.
- Maksimal penukaran 100 poin per pesanan; batas saldo dan total pesanan tetap berlaku.
- Kedaluwarsa poin tidak diaktifkan pada implementasi awal. `expires_at` tetap nullable pada ledger untuk pengembangan kebijakan berikutnya; entry `expire` disediakan sebagai tipe ledger, tetapi belum ada job/RPC kedaluwarsa.

Nilai tersebut adalah usulan awal dan harus disetujui sebelum migration diterapkan di staging. Admin dapat mengubah satu baris pengaturan dengan SQL terotorisasi (RLS membatasi UPDATE ke admin), misalnya:

```sql
update public.loyalty_settings
set earn_points_per_step = 1,
    earn_amount_step = 10000,
    redemption_value = 100,
    max_redeem_points_per_order = 100
where id = true;
```

`max_redeem_points_per_order = NULL` berarti tidak ada batas tetap per pesanan, tetapi saldo dan batas agar diskon tidak melebihi total pesanan tetap diterapkan.

## Alur dan konsistensi

- `create_order` menerima jumlah poin yang diminta, mengunci profil pelanggan untuk menserialisasi penukaran/perolehan, memproses poin yang kedaluwarsa, lalu memvalidasi saldo dan batas dari database. Penukaran dan pembaruan `orders.redeemed_points`, `orders.points_discount`, serta `orders.total` berada dalam transaksi yang sama dengan checkout dan validasi voucher.
- Klien hanya menampilkan pratinjau. Nilai konversi, saldo, dan batas diperiksa kembali di database; klien tidak dapat menulis ledger secara langsung.
- Penukaran poin tidak boleh menutup seluruh total pesanan. Ini mempertahankan nominal pembayaran positif untuk alur pembayaran yang tersedia (termasuk gateway yang menolak nominal nol).
- Trigger setelah pesanan menjadi selesai dan lunas menambahkan poin sekali per pesanan. Indeks unik `(order_id, entry_type)` menjaga idempotensi ketika konfirmasi/status diperbarui berulang.
- Jika pesanan dibatalkan, satu entri `reverse` membalik perolehan dari pesanan itu dan mengembalikan poin yang dipakai untuk checkout tersebut. Jika poin perolehan sudah digunakan di pesanan lain, saldo agregat dapat menjadi negatif sampai pelanggan memperoleh poin lagi; penukaran berikutnya ditolak sampai saldonya cukup.
- Pengaturan awal memberi hak konfigurasi kepada admin melalui RLS. Ledger tidak menyediakan INSERT/UPDATE/DELETE dari klien; trigger menolak UPDATE/DELETE bahkan dari jalur SQL biasa.

## Skenario uji staging

Jangan jalankan migration di produksi. Terapkan `034_loyalty_points.sql` hanya di staging setelah konfigurasi default disetujui.

1. **Perolehan dan konfirmasi berulang:** atur aturan 1 poin per Rp10.000. Selesaikan pesanan berbayar dengan subtotal bersih Rp25.000. Saldo bertambah 2 poin. Ulangi pemanggilan konfirmasi penerimaan atau perbarui status terkait; hanya boleh ada satu entri `earn` untuk order.
2. **Penukaran normal:** dengan saldo cukup dan aturan Rp100/poin, tukar 10 poin pada pesanan Rp5.000. Pesanan menyimpan `redeemed_points = 10`, `points_discount = 1000`, total berkurang Rp1.000, dan ledger mendapat satu `redeem` bernilai -10.
3. **Melebihi saldo:** minta jumlah poin lebih besar dari saldo. RPC `create_order` harus gagal dan transaksi tidak boleh meninggalkan order, perubahan stok, atau entri ledger.
4. **Melebihi batas pesanan:** minta poin lebih besar dari `max_redeem_points_per_order`; checkout harus ditolak server-side.
5. **Batas total pembayaran:** minta poin yang nilai rupiahnya sama dengan atau lebih besar dari total pesanan setelah diskon voucher; checkout harus ditolak dan semua perubahan transaksi dibatalkan. Pratinjau checkout membatasi jumlah agar tersisa minimal Rp1.
6. **Refund/pembatalan:** batalkan pesanan yang memperoleh poin dan/atau menukar poin. Pastikan ada satu entri `reverse` yang meniadakan dampak `earn` dan mengembalikan penukaran, tanpa mengubah entri lama.
7. **Dua checkout bersamaan:** pada akun yang sama, kirim dua checkout yang masing-masing mencoba memakai saldo penuh. Penguncian baris profil harus membuat paling banyak satu checkout berhasil; saldo ledger tidak boleh terpakai ganda.
8. **RLS dan append-only:** sebagai pengguna lain, pastikan ledger tidak terlihat. Coba INSERT/UPDATE/DELETE langsung sebagai authenticated; semua harus ditolak. Pastikan admin dapat membaca konfigurasi dan memperbaruinya.

Pemeriksaan ledger staging:

```sql
select user_id, entry_type, points, order_id, created_at, expires_at
from public.loyalty_ledger
where user_id = 'UUID_PENGGUNA_UJI'
order by created_at, id;

select coalesce(sum(points), 0) as saldo_poin
from public.loyalty_ledger
where user_id = 'UUID_PENGGUNA_UJI';

select id, redeemed_points, points_discount, subtotal, discount_amount, total, status, payment_status
from public.orders
where id = 'UUID_PESANAN_UJI';
```
