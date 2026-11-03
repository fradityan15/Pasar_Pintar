# Audit log, Super Admin, dan ekspor SIKP

## Status format SIKP

Format resmi SIKP, nama/urutan kolom, kode referensi, dan aturan agregasi belum tersedia di repository. Ekspor ini **belum merupakan format SIKP resmi**. Pemetaan awal memakai header placeholder yang eksplisit dan harus diganti setelah pemilik proyek memberikan templat atau spesifikasi resmi.

Konfigurasi aktif tersimpan di `public.sikp_export_mapping` pada kolom JSONB `columns`; template awal yang dilacak di repo ada pada [`config/sikp-mapping.json`](../config/sikp-mapping.json). Contoh awal:

```json
[
  { "header": "PLACEHOLDER_ORDER_REFERENCE", "source": "order_no" },
  { "header": "PLACEHOLDER_PAYMENT_DATE", "source": "paid_date" },
  { "header": "PLACEHOLDER_ORDER_TOTAL", "source": "order_total" },
  { "header": "PLACEHOLDER_UMKM_NAMES", "source": "umkm_names" }
]
```

Server hanya menerima sumber `order_no`, `paid_date`, `order_total`, dan `umkm_names`; pemetaan tidak dapat menentukan SQL atau kolom bebas. Data pelanggan seperti nama, nomor telepon, alamat, dan email sengaja tidak disertakan. Satu baris mewakili satu pesanan, dengan nama UMKM terkait digabungkan. `order_total` adalah total order tercatat dan bukan alokasi nilai per UMKM. Setelah format resmi disediakan, tinjau ulang sumber, definisi nominal, granularitas baris, filter, serta kebutuhan minimisasi data sebelum mengganti placeholder.

Perubahan pemetaan dilakukan Super Admin melalui halaman `/admin/sikp`. Ekspor menggunakan rentang tanggal pembayaran WIB, hanya untuk pesanan berstatus pembayaran `dibayar` yang belum dibatalkan, dibatasi maksimal 367 hari, dan setiap ekspor dicatat ke `audit_logs`.

## Peran dan audit log

- `admin` tetap menjalankan operasional harian.
- `super_admin` mewarisi akses operasional admin dan memiliki akses khusus pengelolaan peran, audit log, dan ekspor SIKP.
- `audit_logs` mencatat perubahan peran, konfirmasi pembayaran, perubahan status penarikan, CRUD voucher, perubahan verifikasi UMKM, penyesuaian stok melalui `stock_movements`, perubahan pemetaan, dan ekspor.
- Audit log append-only: tidak ada hak tulis klien dan trigger menolak UPDATE/DELETE.
- Halaman dan RPC memeriksa peran di server/database; route guard hanya lapisan UI.

## Penerapan dan pengujian

Jangan jalankan migration di produksi. Tinjau lalu terapkan `035_super_admin_audit_sikp.sql` hanya di staging. Pastikan setidaknya satu akun Super Admin ditetapkan oleh operator database tepercaya setelah migration—migration tidak menaikkan akun otomatis.

1. Login sebagai admin biasa; `/admin/audit-log` dan `/admin/sikp` harus ditolak, menu khusus tidak muncul, dan RPC ekspor/pemetaan harus menolak akses.
2. Login sebagai Super Admin; muat audit log, filter aksi/entitas, ubah pemetaan, dan ekspor tanggal uji.
3. Sebagai admin, lakukan konfirmasi pembayaran, proses penarikan, ubah voucher, verifikasi UMKM, dan penyesuaian stok. Pastikan setiap aksi yang benar-benar mengubah data menambah satu audit event dengan aksi dan identitas entitas yang sesuai.
4. Ubah role pengguna lewat RPC Super Admin; pastikan `before.role`/`after.role` tercatat. Akun tidak boleh mengubah role-nya sendiri.
5. Sebagai authenticated, coba SELECT audit log sebagai admin biasa serta UPDATE/DELETE audit log sebagai Super Admin; SELECT harus dibatasi oleh RLS dan perubahan harus ditolak.
6. Konfigurasi header uji dengan tanda kutip dan ekspor transaksi berisi karakter koma/tanda kutip; pastikan CSV ter-escape dengan benar.
7. Bandingkan data ekspor dengan pesanan staging yang dibayar di rentang WIB. Pastikan data pribadi pelanggan tidak terdapat di file dan audit mencatat rentang serta jumlah baris.

Migration menambahkan enum `super_admin`, jadi urutan staging harus memastikan migration selesai sebelum menggunakan peran baru. Set akun Super Admin melalui prosedur operator tepercaya, bukan melalui klien.
