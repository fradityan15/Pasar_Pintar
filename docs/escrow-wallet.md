# Escrow dan saldo seller (ledger internal)

Implementasi ini adalah pembukuan internal. Aplikasi tidak menyimpan atau memindahkan uang sungguhan dan tidak menyediakan transfer bank.

## Migration dan konfigurasi

Terapkan `supabase/migrations/031_seller_escrow_wallet_ledger.sql` hanya di project staging setelah migration order/payment yang berlaku. Tidak ada migration lama yang diubah. Default konfigurasi awal adalah komisi platform 10% dan auto-confirm 7 hari; keduanya disimpan di `platform_financial_settings`, bukan ditanam sebagai nilai dalam perhitungan. Admin dapat mengubahnya melalui `admin_update_financial_settings(p_commission_percent, p_auto_confirm_days)`.

Aktifkan ekstensi `pg_cron` pada project staging agar migration menjadwalkan `process_due_order_auto_confirm()` setiap jam pada menit ke-15. Jika ekstensi tidak aktif saat migration diterapkan, auto-confirm tetap dapat dijalankan oleh pemanggil service-role yang tepercaya, tetapi tidak ada jadwal otomatis; aktifkan pg_cron lalu jadwalkan RPC tersebut sebelum menganggap auto-confirm aktif.

## Kebijakan buku besar

- Setelah order berstatus lunas, trigger database membuat `escrow_holds` per UMKM dari subtotal item toko itu.
- Setelah status order menjadi `selesai`, escrow dirilis sekali: `sale_credit` mencatat nilai kotor, `commission_debit` mencatat komisi negatif, dan saldo tersedia adalah jumlah signed ledger. Saldo ditahan dihitung dari escrow berstatus `held`.
- Pengajuan menarik saldo langsung menambahkan `withdrawal_debit` negatif dalam transaksi yang sama dengan permintaan; row lock UMKM menserialisasi request bersamaan. Jika admin menolak permintaan, `withdrawal_reversal` positif mengembalikan cadangan ke saldo.
- Alur pencairan presentasi: pembeli mengonfirmasi penerimaan, saldo bersih tercatat sebagai saldo tersedia seller, seller mengajukan pencairan, lalu admin menyetujui atau menolak. Untuk presentasi, admin dapat mengubah status menjadi `paid`; seller melihat pencairan berhasil di riwayat. Status `paid` hanya simulasi dan tidak mengirim uang ke rekening atau menambah saldo ledger.
- Ringkasan toko menampilkan total pencairan berstatus `paid` secara terpisah dari omzet penjualan dan memperbaruinya setiap 30 detik. Nilai ini merupakan jumlah simulasi pencairan dan tidak membuktikan uang sungguhan masuk ke rekening seller.
- Refund escrow yang belum dirilis dicatat sebagai entri informasi `escrow_refund` (tidak masuk agregasi saldo). Refund atas escrow yang sudah dirilis menambahkan `refund_debit` negatif untuk nilai net yang pernah dikreditkan. Jika seller telah menarik nilai itu, saldo ledger dapat menjadi negatif sebagai kewajiban internal sampai tertutup oleh kredit berikutnya.
- `wallet_ledger` menolak UPDATE/DELETE lewat trigger; klien juga tidak memiliki hak tulis langsung. Penyesuaian dilakukan dengan entri kompensasi baru, bukan mengedit histori.

## Uji staging

Gunakan akun seller/admin dan transaksi sandbox. Jangan jalankan pada produksi.

1. **Order selesai dan komisi**: lakukan pembayaran sandbox sampai `payment_status='dibayar'`; verifikasi `escrow_holds.status='held'`. Lalu tandai dikirim dan konfirmasi penerimaan pembeli atau tunggu auto-confirm. Periksa:

   ```sql
   select e.order_id, e.umkm_id, e.amount, e.status, e.released_at,
          sum(l.amount) filter (where l.entry_type in ('sale_credit', 'commission_debit')) as net_ledger
   from public.escrow_holds e
   left join public.wallet_ledger l
     on l.order_id = e.order_id and l.umkm_id = e.umkm_id
   where e.order_id = '<order-uuid>'
   group by e.order_id, e.umkm_id, e.amount, e.status, e.released_at;
   ```

   Untuk komisi `c` persen, harapkan `sale_credit = gross`, `commission_debit = -round(gross*c/100)`, `net_ledger = gross - commission`, dan status escrow `released`. Panggil `release_escrow` lagi pada role service/admin di staging; jumlah ledger harus tetap sama.
2. **Penarikan melebihi saldo**: login sebagai seller dengan saldo `available_balance`, lalu panggil `request_withdrawal(available_balance + 1, gen_random_uuid())`. RPC harus menolak dengan `Saldo tersedia tidak mencukupi` dan tidak membuat request/ledger debit.
3. **Dua pengajuan bersamaan**: sebagai seller yang saldo tersedia cukup untuk satu dari dua pengajuan, jalankan pada dua sesi transaksi yang berbeda:

   ```sql
   select public.request_withdrawal(<amount>, gen_random_uuid());
   ```

   Kedua request mengunci row UMKM yang sama. Satu request dapat berhasil, request kedua setelah lock dilepas menghitung saldo ledger terbaru dan ditolak; saldo tidak menjadi negatif akibat pengajuan bersamaan.
4. **Penolakan admin**: admin jalankan `select public.admin_process_withdrawal('<withdrawal-uuid>', 'rejected', 'Alasan uji');`. Pastikan ledger menambah `withdrawal_reversal` positif dan saldo tersedia pulih.
5. **Penandaan lunas**: setelah transfer eksternal benar-benar disimulasikan/dilakukan, admin jalankan `select public.admin_process_withdrawal('<withdrawal-uuid>', 'paid', 'Transfer uji');` hanya terhadap request berstatus `approved`.
6. **Kebijakan append-only**: sebagai authenticated, uji `update public.wallet_ledger ...` dan `delete from public.wallet_ledger ...`; keduanya harus ditolak. Pastikan penjual hanya melihat entri dan permintaannya sendiri dan admin dapat membaca antrean melalui `admin_list_withdrawals()`.

Fungsi `request_withdrawal` dan `admin_process_withdrawal` memerlukan konteks autentikasi Supabase yang sesuai. Untuk uji SQL, gunakan SQL editor staging dengan role/JWT yang sesuai; jangan menurunkan batas role atau membuka hak tulis ledger untuk mempermudah pengujian.
