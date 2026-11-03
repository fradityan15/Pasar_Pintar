# Midtrans Sandbox

Checkout menyediakan Midtrans Sandbox untuk QRIS dan Virtual Account; metode transfer manual yang sudah ada tetap tersedia dan tetap diverifikasi admin. Order, nominal, expiry, serta status pembayaran tetap diverifikasi di server/database. Jangan memakai kredensial produksi untuk pengujian ini.

## Setup staging

1. Buat atau pilih project Supabase staging dan project Midtrans Sandbox.
2. Tinjau migration baru `supabase/migrations/030_midtrans_sandbox_payments.sql`, lalu terapkan seluruh migration yang belum diterapkan di staging. Jangan menjalankannya pada project produksi sebagai bagian dari pengujian.
3. Ambil **Server Key Sandbox** dari dashboard Midtrans. Simpan melalui Supabase Dashboard → Edge Functions → Secrets, atau dari lingkungan shell/secret manager yang aman:

   ```sh
   supabase secrets set MIDTRANS_SERVER_KEY="$MIDTRANS_SERVER_KEY"
   ```

   Atur variabel shell tersebut hanya dari secret manager; jangan mengetik nilai key langsung ke command history. Jangan meletakkan key di `.env`, source frontend, repository, atau variabel berawalan `VITE_`. Supabase menyediakan `SUPABASE_URL`, `SUPABASE_ANON_KEY`, dan `SUPABASE_SERVICE_ROLE_KEY` kepada Edge Functions; service-role key tidak boleh dikirim ke browser.
4. Deploy `create-payment` dan `payment-webhook` hanya ke project staging:

   ```sh
   supabase functions deploy create-payment
   supabase functions deploy payment-webhook
   ```

   `supabase/config.toml` mewajibkan JWT pada `create-payment`; verifikasi JWT dimatikan hanya untuk webhook karena notifikasi Midtrans ditandatangani dengan signature key.
5. Daftarkan URL notifikasi berikut pada konfigurasi **Payment Notification URL** di dashboard Midtrans Sandbox:

   ```text
   https://<project-ref>.supabase.co/functions/v1/payment-webhook
   ```

   Pastikan URL menggunakan project staging yang benar. Jangan daftarkan URL produksi untuk pengujian sandbox.
6. Di `.env` lokal, isi hanya `VITE_SUPABASE_URL` dan `VITE_SUPABASE_ANON_KEY` dari project staging. File `.env.example` sengaja hanya memuat nama variabel tanpa nilainya.

## Cara kerja

- UI mengirim `order_id` ke `create-payment`; Edge Function mengambil pengguna dari JWT, memastikan order dimiliki pengguna, lalu RPC `begin_midtrans_payment` mengunci order, memvalidasi status dan expiry, dan mengambil total serta metode dari database.
- Edge Function memakai Charge API Sandbox untuk membuat transaksi QRIS/VA, menyimpan `provider_ref`, instruksi, status, dan payload respons. Jika hasil request tidak pasti, function memeriksa status transaksi Midtrans terlebih dahulu sebelum mencoba membuatnya kembali.
- `payment-webhook` memvalidasi signature SHA-512 Midtrans sebelum mengubah database. RPC service-role mengunci payment dan order, mencocokkan nominal, mengabaikan notifikasi duplikat, lalu menetapkan `paid_at` dan menulis `order_status_logs` hanya untuk pembayaran yang sah.
- Perubahan order menjadi `dibayar` membuat notifikasi pembayaran di header admin (pembaruan maksimal setiap 30 detik). Ini mencakup pembayaran Midtrans dan transfer yang diverifikasi admin, tidak termasuk COD. Notifikasi mencatat konfirmasi dalam aplikasi; notifikasi tersebut bukan bukti dana diterima rekening platform atau transfer bank.
- Status pembayaran Midtrans dibaca pemilik order melalui RLS dan dipolling ringan oleh halaman pembayaran. Pembayaran transfer manual tidak memakai webhook dan tetap mengikuti verifikasi admin.
- Jika pembayaran sukses tiba setelah order sudah kedaluwarsa/dibatalkan, order tidak dibuka kembali dan payment dicatat sebagai `paid_late` untuk rekonsiliasi manual. Notifikasi refund juga memerlukan rekonsiliasi manual, karena alur refund otomatis belum termasuk implementasi ini.

## Skenario uji sandbox

Gunakan Midtrans Sandbox Simulator untuk menghasilkan transaksi uji. Periksa tampilan UI, baris `payments` dan `orders`, serta log `order_status_logs` di project staging.

| Skenario | Hasil yang diharapkan |
|---|---|
| QRIS berhasil | Charge mengembalikan URL QR; setelah notifikasi `settlement` valid, order menjadi `dibayar`, `paid_at` terisi, dan log status dipasang satu kali. |
| VA berhasil | UI menampilkan nomor VA (atau kode biller/kode bayar untuk Mandiri); notifikasi `settlement` valid memperbarui order seperti QRIS. |
| Transaksi gagal | Notifikasi `deny`/`failure` tidak menandai order dibayar; payment berstatus gagal. |
| Transaksi kedaluwarsa | Notifikasi `expire` menandai payment expired, membatalkan order yang masih menunggu, dan memanggil pengembalian stok yang sudah disediakan oleh mekanisme database. |
| Webhook duplikat | Kirim notifikasi sukses yang sama lebih dari sekali; status/log tidak berlipat dan order tetap hanya memiliki satu transisi pembayaran. |
| Signature palsu | Ubah `signature_key`; endpoint menolak dengan HTTP 401 dan tidak mengubah database. |
| Nominal tidak cocok | Kirim notifikasi bertanda tangan valid tetapi dengan `gross_amount` yang berbeda di lingkungan uji; RPC menolak dan order tidak dibayar. Jangan mengubah transaksi nyata untuk pengujian ini. |
| Order milik pengguna lain / sudah lunas / kedaluwarsa | Pemanggilan `create-payment` ditolak; tidak ada Charge baru untuk order tersebut. |
| Transfer manual | Pilih metode manual, lakukan transfer simulasi sesuai prosedur proyek, lalu verifikasi pembayaran melalui admin seperti sebelumnya. |

Webhook refund diterima hanya setelah signature valid dan dikembalikan untuk rekonsiliasi manual; status refund/ledger belum diotomatisasi. Pengujian perlu memakai project staging dan transaksi sandbox, bukan kredensial atau data produksi.
