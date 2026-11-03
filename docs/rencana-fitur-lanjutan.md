# Rencana fitur lanjutan PasarPintar

**Status:** dokumen perencanaan; bukan migration atau spesifikasi implementasi final  
**Tanggal:** 2 November 2026

Dokumen ini merancang fondasi payment gateway/webhook, escrow, saldo dan penarikan seller, ongkir/resi/pelacakan, voucher subsidi GBBI, poin loyalitas, serta ekspor SIKP. Tidak ada SQL yang dijalankan dan tidak ada database atau layanan eksternal yang diakses.

## 1. Baseline yang ditemukan

Rujukan utama:

- [001_schema.sql](../supabase/migrations/001_schema.sql): tabel profil, UMKM, katalog, keranjang, pesanan, item, status log, dan pergerakan stok.
- [002_rls_storage.sql](../supabase/migrations/002_rls_storage.sql): RLS aktif pada tabel inti. Order, item order, log status dan stok tidak dapat ditulis langsung oleh klien; mutasi bisnis dilakukan melalui RPC.
- [003_functions.sql](../supabase/migrations/003_functions.sql), [010_buyer_order_completion.sql](../supabase/migrations/010_buyer_order_completion.sql), [011_order_shipment_completion.sql](../supabase/migrations/011_order_shipment_completion.sql), [018_seller_order_action_logs.sql](../supabase/migrations/018_seller_order_action_logs.sql), [023_order_payment_and_reporting_fixes.sql](../supabase/migrations/023_order_payment_and_reporting_fixes.sql), [026_order_role_separation.sql](../supabase/migrations/026_order_role_separation.sql): evolusi fungsi checkout, pembayaran, pembatalan, pengiriman seller, dan penyelesaian oleh pembeli. Definisi yang berlaku harus ditentukan menurut urutan migration aktual saat implementasi.
- [01_setup_payments.sql](../01_setup_payments.sql): tabel `payment_methods`, kolom dan constraint `orders.payment_status`, serta evolusi checkout yang dirujuk migration.
- [004_cron.sql](../supabase/migrations/004_cron.sql): jadwal `expire_unpaid_orders()` setiap jam melalui `pg_cron`; [026_order_role_separation.sql](../supabase/migrations/026_order_role_separation.sql) mencabut eksekusi fungsi kedaluwarsa dari peran klien.
- [015_checkout_payment_options.sql](../supabase/migrations/015_checkout_payment_options.sql), [024_checkout_payment_method_uuid.sql](../supabase/migrations/024_checkout_payment_method_uuid.sql), [026_order_role_separation.sql](../supabase/migrations/026_order_role_separation.sql): checkout terakhir menerima `p_payment_method_id`, produk pilihan, dan `p_shipping_method`; tarif `regular`/`economy` dihitung dengan nominal tetap di SQL.
- [005_umkm_ownership.sql](../supabase/migrations/005_umkm_ownership.sql), [007_seller_orders.sql](../supabase/migrations/007_seller_orders.sql), [023_order_payment_and_reporting_fixes.sql](../supabase/migrations/023_order_payment_and_reporting_fixes.sql): kepemilikan seller diverifikasi di server dan progres kirim ditandai per `order_items.umkm_id`.
- [008_seller_store_settings.sql](../supabase/migrations/008_seller_store_settings.sql): tersedia preferensi nama kurir dan data rekening toko, tetapi itu bukan integrasi tarif, pembuatan pengiriman, atau pencairan dana.
- [orderService.js](../src/services/orderService.js), [adminOrderService.js](../src/services/adminOrderService.js), [sellerOrderService.js](../src/services/sellerOrderService.js), [addressService.js](../src/services/addressService.js), [adminReportService.js](../src/services/adminReportService.js): pemanggil RPC/data yang tersedia di klien.
- [src/services/](../src/services/): tidak ditemukan service untuk payment gateway/webhook, pengiriman eksternal, voucher, poin, saldo/penarikan, atau ekspor SIKP.
- `supabase/functions/` belum ada. Tidak ada migration yang membentuk tabel untuk escrow, voucher, poin, penarikan, shipment, atau audit/ekspor SIKP.

### Siklus order saat ini

```text
checkout
  ├─ non-COD: menunggu_pembayaran / payment_status pending atau belum_dibayar
  │    └─ verifikasi admin transfer: diproses / dibayar / paid_at terisi
  └─ COD: menunggu_diproses / belum dibayar
       └─ seller memproses dan mengirim
            └─ pembeli konfirmasi terima: selesai
                 └─ COD: pembayaran ditandai dibayar pada konfirmasi terima
```

`create_order` saat ini mengunci/validasi stok, membuat order dan `order_items`, mengurangi stok, mencatat `stock_movements`, lalu mengosongkan keranjang dalam satu transaksi. Stok berkurang saat checkout, bukan saat pembayaran. `cancel_order` dan `expire_unpaid_orders` mengembalikan stok lewat `private.restock_order`. Pembayaran transfer diverifikasi lewat `admin_confirm_order_payment`; simulasi pembayaran lama tidak menjadi alur gateway produksi. Nilai status pembayaran terkini mencakup `pending`, `belum_dibayar`, `dibayar`, dan `kedaluwarsa`; status order mencakup `menunggu_pembayaran`, `menunggu_diproses`, `diproses`, `dikirim`, `selesai`, dan `dibatalkan`.

Satu order dapat berisi item dari beberapa UMKM. Karena itu, progres kirim item seller saat ini tidak cukup untuk menyimpan beberapa nomor resi, paket, kurir, atau event pelacakan secara independen.

## 2. Target desain data

Nama dan kolom berikut adalah rancangan konseptual; tipe, constraint final, strategi migrasi/backfill, retensi, serta indeks perlu ditinjau sebelum ditulis sebagai migration. Semua nominal rupiah disimpan sebagai bilangan bulat/`numeric` tanpa floating point.

### 2.1 Pembayaran dan escrow

| Tabel usulan | Data pokok | Tujuan dan integritas |
|---|---|---|
| `payment_attempts` | `id`, `order_id`, `provider`, `provider_reference` unik, `idempotency_key` unik per provider, `amount`, `currency`, `status`, `checkout_url`/instruksi yang aman, `expires_at`, `paid_at`, `failure_code` terbatas, timestamp | Satu order dapat memiliki percobaan ulang yang terukur. Simpan nominal yang diharapkan dari DB; jangan pernah simpan nomor kartu, CVV, private key, atau payload rahasia provider. Batasi state transition dan cegah dua attempt aktif yang saling bertentangan. |
| `payment_webhook_events` | `id`, `provider`, `event_id`, `received_at`, `signature_valid`, `event_type`, `payment_attempt_id`, `payload_digest`, `processing_status`, `processed_at`, `failure_reason` internal | `UNIQUE(provider,event_id)` untuk idempotensi. Simpan digest dan metadata minimum; raw payload hanya bila dibutuhkan untuk dispute, dienkripsi/dibatasi dan diberi masa retensi. Event diterima tidak berarti pembayaran berhasil sampai diverifikasi dan dicocokkan dengan attempt/order. |
| `escrow_accounts` atau akun ledger | `id`, `owner_type`, `owner_id`, `currency`, status, timestamp | Akun logis untuk clearing, escrow, payable seller, fee platform, refund, dan payout. Pertimbangkan satu model ledger double-entry, bukan kolom saldo yang dapat diedit langsung. |
| `financial_ledger_entries` | `id`, `transaction_id`, `account_id`, `order_id`, `seller_umkm_id`, `entry_type`, `amount`, `currency`, `idempotency_key` unik, `created_at`, metadata nonrahasia | Entri immutable dan seimbang per transaksi. Koreksi dilakukan dengan reversal entry, bukan update/delete. Total debit dan kredit harus sama dalam satu mata uang. |
| `seller_withdrawals` | `id`, `umkm_id`, `requested_by`, `amount`, `currency`, snapshot tujuan payout yang terenkripsi atau token provider, `status`, `idempotency_key` unik, `provider_reference`, `reviewed_by`, waktu/status, alasan aman | Request, review, pengiriman payout, gagal, dan reversal dapat diaudit. Detail rekening tidak boleh ikut query publik atau log. |

Saldo seller sebaiknya menjadi **proyeksi ledger**: `tersedia = payable seller yang sudah dilepas - payout yang berhasil - payout yang sedang direservasi`. UI tidak boleh menulis saldo. Fee platform, pajak, pembulatan, refund parsial, chargeback, dan COD belum ditetapkan.

Siklus escrow yang disarankan untuk pembayaran gateway: pembayaran terverifikasi masuk akun clearing/escrow; porsi seller dan fee dihitung server-side; porsi seller menjadi payable tetapi tertahan; setelah semua paket diterima atau aturan dispute berakhir, RPC melepas payable ke saldo seller. Refund/chargeback membuat transaksi kompensasi. COD tidak boleh dianggap dana escrow sampai uang benar-benar dipungut dan disetorkan; butuh alur rekonsiliasi COD yang terpisah.

### 2.2 Tarif, shipment, resi, dan tracking

| Tabel usulan | Data pokok | Tujuan dan integritas |
|---|---|---|
| `shipping_quotes` | `id`, order/user, alamat tujuan snapshot/hash, asal UMKM, provider dan service code, berat, harga dari API, estimasi, `expires_at`, `quote_reference`, status penggunaan | Kutipan harga yang dipilih, memiliki masa berlaku dan tidak dapat diganti oleh nilai biaya dari browser saat checkout. Harga final dikonfirmasi server/provider. |
| `shipments` | `id`, `order_id`, `umkm_id`, `provider`, service, `order_item_ids` atau hubungan melalui tabel detail, `tracking_number`, status provider/internal, biaya final, label reference, waktu pickup/antar/terkirim, `quote_id`, idempotency key | Satu shipment per paket seller (atau per paket provider bila pecah paket); unik sesuai referensi provider. Simpan salinan data untuk histori. Buat akses seller berdasarkan UMKM yang dimiliki. |
| `shipment_items` (bila satu paket dapat dipecah/dirakit ulang) | `shipment_id`, `order_item_id`, quantity | Menjaga kuantitas tiap paket, dengan constraint agar total tidak melebihi quantity order item. |
| `shipment_tracking_events` | `shipment_id`, provider event ID, status code, deskripsi yang sudah disanitasi, lokasi, waktu event provider, waktu diterima | `UNIQUE(provider,event_id)` bila provider memberi ID event; urutkan memakai waktu provider dan tahan event duplikat/terlambat. |

`orders.shipping_cost` tetap menjadi total snapshot order untuk kompatibilitas laporan/checkout; biaya dan subsidi aktual per shipment/merchant perlu rincian terpisah. Alokasi ongkir ke beberapa UMKM harus didefinisikan sebelum checkout nyata.

### 2.3 Voucher subsidi GBBI

| Tabel usulan | Data pokok | Tujuan dan integritas |
|---|---|---|
| `gbbi_vouchers` | kode unik, status, waktu mulai/akhir, kuota total, kuota per user, batas transaksi, minimum belanja, jenis cakupan (produk/ongkir/keduanya), maksimum subsidi, anggaran, pendana, aturan wilayah/merchant/kategori, timestamp | Hanya admin dengan permission GBBI mengelola. Validasi nilai, rentang waktu, batas, dan status di DB. |
| `gbbi_voucher_claims` | `id`, voucher/user/order, status (`reserved`, `redeemed`, `released`, `reversed`), nominal diskon aktual, kuota/anggaran yang direservasi, idempotency key, waktu | Unique per order/voucher; indeks unik parsial untuk batas klaim aktif/penggunaan. Reservasi atomik di RPC memakai row lock/advisory lock dan constraint, bukan hitung-kuota di klien. |
| `voucher_budget_ledger` (opsional tetapi direkomendasikan) | voucher, claim/order, perubahan anggaran bertanda, referensi reversal | Rekonsiliasi subsidi dan cegah anggaran agregat melewati plafon ketika klaim bersamaan. |

Klaim sebaiknya direservasi dalam transaksi `create_order`; jika checkout gagal tidak ada klaim. Pembatalan/kedaluwarsa melepas reservasi sekali saja. Pembayaran berhasil mengubahnya menjadi redeemed. Refund membalik subsidi menurut kebijakan yang diputuskan.

### 2.4 Poin loyalitas

| Tabel usulan | Data pokok | Tujuan dan integritas |
|---|---|---|
| `loyalty_accounts` | `user_id` unik, balance/cache, timestamp | Saldo cache bila perlu; sumber kebenaran tetap ledger. |
| `loyalty_ledger_entries` | user, order, jenis (`earn`, `redeem`, `expire`, `reverse`), poin bertanda, idempotency key unik, waktu berlaku/kedaluwarsa, metadata | Immutable, saldo tidak dapat menjadi negatif, setiap operasi transaksi atomik. Jangan menerima nilai poin dari klien. |

Perolehan poin dilakukan pada event final yang disepakati (disarankan saat order selesai, bukan sekadar dibuat); penggunaan poin mereservasi/mengurangi dalam checkout dan dibalik jika order batal. Aturan kedaluwarsa dan retur harus deterministik.

### 2.5 Ekspor SIKP dan audit

| Tabel usulan | Data pokok | Tujuan dan integritas |
|---|---|---|
| `sikp_export_jobs` | `id`, requester, periode/filter, format/schema version, status job, waktu mulai/selesai, jumlah baris, path objek privat, expiry, checksum, error code nonrahasia | Ekspor besar dibuat async oleh worker/Edge Function; download memakai signed URL singkat. Jangan menjadikan bucket publik. |
| `audit_logs` | actor, action, resource type/id, waktu, request/correlation ID, hasil, metadata yang sudah disaring, sumber perubahan | Insert-only melalui fungsi tepercaya/trigger untuk tindakan finansial, verifikasi, ekspor, perubahan permission dan voucher. Jangan masukkan secret, token, data rekening penuh, atau payload webhook mentah. |

Saat ini migration `001_schema.sql` tidak membuat tabel `audit_logs` dan enum `user_role` hanya mempunyai `admin` serta `customer`. Jika SIKP hanya untuk Super Admin, perlu keputusan apakah menambah role `super_admin` atau membuat tabel permission/capability khusus. Jangan menganggap `admin` saat ini otomatis setara dengan Super Admin.

## 3. RPC dan kontrak server yang diusulkan

RPC berjalan dalam transaksi DB, validasi otorisasi dan status di server, dan tidak dipercaya untuk nilai yang berasal dari klien tanpa verifikasi. Semua fungsi `SECURITY DEFINER` perlu `search_path` eksplisit, hak eksekusi `PUBLIC/anon` dicabut, pemeriksaan actor eksplisit, dan uji privilege.

| RPC usulan | Perilaku |
|---|---|
| `record_payment_attempt(p_order_id, p_provider, p_idempotency_key)` | Hanya pemilik order yang belum kedaluwarsa boleh memulai. Ambil amount dari `orders.total`; Edge Function membuat sesi ke provider dan mengaitkan reference. Hindari mengembalikan secret credential. |
| `apply_payment_webhook(p_provider, p_event_id, ...)` internal | Dipanggil hanya setelah Edge Function memverifikasi signature, event ID, amount, mata uang, reference dan status final. Lock payment attempt/order; event duplicate menjadi no-op. Tandai `payment_status='dibayar'`, set `paid_at` dari timestamp provider tervalidasi, transisi ke `diproses`, log status, dan buat posting clearing/escrow atomik. Jangan membuka RPC ini ke `anon`/`authenticated`. |
| `reconcile_payment_attempts()` internal/cron | Menemukan attempt tertahan dan membandingkan ke provider dengan rate limit. Event webhook tetap jalur utama; polling pemulihan tidak menggandakan ledger. |
| Perubahan `create_order(...)` | Tetap menjadi otoritas harga, stok dan alamat. Tambahkan quote shipment yang valid, voucher/poin opsional, biaya/discount yang dihitung/di-lock server, idempotency checkout. Hindari memecah transaksi checkout menjadi mutasi klien yang dapat meninggalkan order tanpa klaim/payment intent. |
| `reserve_gbbi_voucher(...)` / helper privat di checkout | Kunci voucher dan counter/ledger; validasi masa berlaku, wilayah, pemilik, kuota, anggaran, minimum belanja, limit per user, satu order; simpan nominal subsidi yang dihitung server. Mutasi transaksi DB-only. |
| `redeem_loyalty_points(...)` / helper privat di checkout | Validasi saldo ledger dan batas konversi dalam lock transaksi; reservasi/redeem atomik dengan voucher dan total order. |
| `release_order_escrow(p_order_id)` internal | Idempotent; cek pembayaran benar-benar masuk, semua shipment/receiving memenuhi aturan, tiada dispute/refund/chargeback, dan buat posting ledger balanced. Callable oleh event completion/job tepercaya, bukan input klien bebas. |
| `open_seller_withdrawal(p_umkm_id, p_amount, p_destination_id, p_idempotency_key)` | Verifikasi pemilik aktif, rekening terverifikasi, batas nominal dan saldo tersedia; reserve payable dalam ledger dan buat withdrawal dalam transaksi. |
| `review_seller_withdrawal(p_withdrawal_id, p_decision, ...)` | Hanya finance/admin permission; approval menyiapkan payout eksternal, penolakan melepas reserve. |
| `finalize_seller_payout(...)` internal | Hanya hasil provider yang tervalidasi dapat menyelesaikan/menolak payout; idempotensi terhadap callback/reconciliation. Payout gagal membalik reserve; payout sukses mencatat debit akhir. |
| `record_shipping_quote(...)` / checkout helper | Simpan quote dari provider yang valid; verifikasi expiry, alamat, origin, berat dan service code. Requote bila expired. |
| `attach_shipment_tracking(...)` | Pemilik UMKM yang terkait order dapat mengirim paket hanya ketika status layak; nomor resi harus berasal dari API shipment atau ditandai tegas sebagai resi manual. |
| `apply_shipment_tracking_event(...)` internal | Terima callback terverifikasi provider; deduplikasi event, simpan histori, update agregat status tanpa menerima status sewenang-wenang dari browser. |
| `expire_reserved_checkout_state()` | Worker terjadwal melepas voucher/poin/shipping quote/intent yang ditahan untuk order yang kedaluwarsa dan mengembalikan stok dengan semantik idempotent saat ini. |
| `create_sikp_export_job(...)` / `complete_sikp_export(...)` | Validasi permission Super Admin, periode/schema, pencatatan audit; worker membuat file di bucket privat dan menandai job dengan expiry/checksum. Hasil hanya lewat signed URL terbatas. |

### Aturan idempotensi lintas RPC

- Kunci eksternal utama adalah `(provider, event_id)` webhook dan `(provider, provider_reference)` attempt; kunci permintaan klien diperlukan untuk retry create-session/checkout/payout.
- Perubahan order, ledger, klaim voucher/poin, stok, dan status payment dikerjakan dalam transaksi DB yang sama jika melibatkan data DB.
- Webhook terlambat setelah order dibatalkan/kedaluwarsa tidak boleh menandai order sebagai normal `diproses`: masukkan ke status exception/reconciliation dan kebijakan refund/manual review; jangan menghidupkan order tanpa pemeriksaan.
- Callback gagal atau data provider tidak cocok harus dicatat dan dapat direkonsiliasi, bukan success-shaped response.

## 4. Alur status order yang terdampak

```text
Checkout non-COD:
  menunggu_pembayaran + pending
    ├─ gateway confirmed -> diproses + dibayar + paid_at
    ├─ expires -> dibatalkan + kedaluwarsa + stok/claim reserve dilepas
    └─ buyer/admin cancel -> dibatalkan + refund bila pembayaran telanjur masuk

Checkout COD:
  menunggu_diproses + belum_dibayar
    -> diproses -> dikirim -> selesai + dibayar saat pembeli menerima
    -> rekonsiliasi pungutan COD sebelum membentuk saldo seller yang dapat dicairkan

Order yang dibayar:
  diproses -> shipment per UMKM/paket dibuat -> dikirim saat semua paket memenuhi
    -> selesai oleh buyer / aturan auto-complete yang kelak disetujui
    -> escrow dilepas ke payable seller setelah syarat selesai/dispute terpenuhi
```

Prinsip transisi:

1. `payment_status` dan `order_status` adalah dimensi terkait tetapi berbeda. `dibayar` tidak boleh disimpulkan dari tombol UI, status kirim, atau data redirect provider.
2. `menunggu_pembayaran -> dibatalkan/kedaluwarsa` menutup jalur pembayaran biasa. Pembayaran setelah expiry perlu dispute/refund workflow.
3. Escrow tidak melepas dana hanya karena `seller_ship_order` menandai `dikirim`. Gunakan penerimaan pembeli dan/atau batas dispute yang eksplisit.
4. Karena paket seller bisa berbeda, `orders.status='dikirim'` hanya ketika semua shipment/item yang diwajibkan sudah diserahkan. Simpan status parcel individual.
5. Refund, chargeback, dispute dan seller cancellation belum ada pada enum/status sekarang; jangan menambah status tanpa memetakan laporan, dashboard, UI, log, stok, voucher, poin, dan ledger.
6. COD tidak mengikuti jalur payment gateway yang sama. Saat ini `confirm_order_received` menandai COD dibayar; desain baru perlu membedakan konfirmasi penerimaan dari settlement uang COD.

## 5. RLS, akses, dan penanganan rahasia

Pertahankan prinsip di [002_rls_storage.sql](../supabase/migrations/002_rls_storage.sql) dan helper kepemilikan di [005_umkm_ownership.sql](../supabase/migrations/005_umkm_ownership.sql):

- Aktifkan RLS pada seluruh tabel baru. Tidak ada kebijakan `USING (true)` bagi tabel transaksi, saldo, voucher claim, webhook, payout, audit, atau ekspor.
- Buyer hanya membaca payment attempts, klaim voucher/poin, shipment, dan tracking untuk order miliknya. Buyer tidak bisa menulis konfirmasi pembayaran, ledger, tracking provider, atau status.
- Seller hanya membaca shipment/ledger/withdrawal milik UMKM yang dimilikinya; data buyer yang ditampilkan dibatasi sesuai kebutuhan fulfillment. Tidak boleh membaca rekening/ledger UMKM lain atau semua order secara langsung.
- Nilai transaksi keuangan hanya dapat diubah lewat RPC tepercaya yang menjaga status dan keseimbangan ledger. Cabut hak insert/update/delete langsung dari `anon`/`authenticated` untuk ledger, webhook, audit, payout, claims dan tabel internal.
- Admin mengelola konfigurasi program, menyelesaikan pengecualian dan meninjau payout sesuai permission. Ekspor SIKP memerlukan capability/role khusus setelah keputusan akses; audit actor dan setiap unduhan.
- Edge Function memakai verifikasi JWT untuk permintaan user, lalu memvalidasi kepemilikan terhadap DB. `service_role` hanya di environment Edge Function tepercaya, tidak pernah di bundle Vue atau variabel `VITE_*`.
- Bucket ekspor SIKP privat. Signed URL singkat, satu job/actor, dan akses dicatat.
- Jangan mencatat signature, secret, token, rekening penuh, atau raw payload sensitif di log. Simpan secret dengan Supabase secrets; rotasi key dan dukung key version saat provider mengharuskan overlap.

## 6. Struktur Supabase Edge Functions yang diusulkan

```text
supabase/
  functions/
    _shared/
      auth.ts                 # verifikasi JWT, CORS allowlist, response/error helpers
      http.ts                 # validasi request, timeout, request/correlation ID
      providers/
        payments.ts           # interface provider; adapter spesifik setelah provider dipilih
        shipping.ts           # interface quote/create/track
    payment-create-session/
      index.ts                # user JWT -> validasi order/RPC -> provider checkout
    payment-webhook/
      index.ts                # raw body -> signature/timestamp -> dedup -> RPC internal
    payment-reconcile/
      index.ts                # cron/secret invocation -> cek attempt tertunda
    shipping-quote/
      index.ts                # user JWT -> quote per tujuan/asalan/berat
    shipping-create/
      index.ts                # seller JWT -> buat label/pickup shipment
    shipping-webhook/
      index.ts                # validasi webhook tracking provider -> RPC internal
    seller-payout/
      index.ts                # permintaan payout terotorisasi dan idempotent
    seller-payout-webhook/
      index.ts                # status payout terverifikasi -> finalize RPC
    sikp-export/
      index.ts                # cek capability, buat job, file ke bucket private
    sikp-export-worker/
      index.ts                # query terkontrol, generate file/version, update job
```

Nama fungsi dapat digabung jika provider mengizinkan dan batas keamanan tetap jelas. Pisahkan endpoint webhook dari API user biasa; verifikasi signature pada **raw request body** sebelum parsing/aksi, validasi timestamp untuk replay protection, bandingkan amount/currency/provider reference, batasi ukuran request, dan gunakan idempotensi DB.

Rahasia contoh nama (bukan nilai) disimpan dengan `supabase secrets set PAYMENT_PROVIDER_API_KEY=... PAYMENT_WEBHOOK_SECRET=... SHIPPING_PROVIDER_API_KEY=... SHIPPING_WEBHOOK_SECRET=... PAYOUT_PROVIDER_API_KEY=... SIKP_EXPORT_SIGNING_KEY=...`. `SUPABASE_URL` dan `SUPABASE_SERVICE_ROLE_KEY` hanya tersedia di runtime function yang memerlukan akses server; jangan pernah memakai prefix `VITE_` atau mengembalikan nilainya ke client. Untuk invocation cron gunakan auth secret/otorisasi job terpisah dan rotasi berkala. Tidak ada `.env` yang dibaca atau disertakan dalam rancangan ini.

## 7. Urutan implementasi dan dependensi

```text
0. Putuskan provider, biaya/komisi, dispute/COD, kebijakan voucher/poin, format & akses SIKP
   └─> 1. Fondasi ledger, status, idempotensi, audit, RLS dan observability
       ├─> 2. Payment gateway + webhook + reconciliation
       │    └─> 3. Escrow + saldo seller + payout/withdrawal
       ├─> 4. Shipping quote/label/tracking (dapat paralel dengan pembayaran)
       ├─> 5. Voucher GBBI (bergantung pada kalkulasi harga checkout + pendanaan/ledger)
       ├─> 6. Loyalty (bergantung pada definisi final order, cancel/refund dan ledger poin)
       └─> 7. SIKP export (bergantung pada skema settlement/ledger yang stabil + permission)
```

| Tahap | Hasil yang diuji sebelum tahap berikutnya |
|---|---|
| 0 — keputusan produk dan provider | Kontrak provider sandbox/production, biaya, skenario callback/retry, aturan COD/refund, kebijakan kuota/poin, pemilik data/akses SIKP ditandatangani. |
| 1 — keselamatan transaksi | Migration tabel internal dan RLS; ledger double-entry invariant; state machine; idempotency; audit; tests concurrency dan akses; rekonsiliasi awal tanpa pengiriman dana. |
| 2 — gateway | Adapter sandbox, create-session, signature webhook, dedup, amount/reference validation, expired/late callback, polling reconciliation; pertahankan verifikasi manual sebagai fallback yang tercatat selama cutover. |
| 3 — escrow/wallet/payout | Pencatatan dana masuk, hold/release, refund/reversal, saldo available/pending, rekening tujuan terverifikasi, maker-checker approval bila dipilih, payout sandbox dan reconcile. |
| 4 — logistik | Mapping alamat/region ke API provider, quote server-side yang expired, snapshot biaya, create shipment per merchant, resi/label, callback tracking dan event idempotency; tetap dukung jalur manual untuk exception. |
| 5 — subsidi GBBI | Claim/reserve atomik, penggunaan budget, expiry/cancel release, scope diskon, rekonsiliasi sponsor dan audit; uji dua klaim simultan pada kuota terakhir. |
| 6 — loyalitas | Rule engine versi/konfigurasi, accrue pada event final yang disetujui, redeem atomik, expiry/refund reversal; uji saldo negatif dan double event. |
| 7 — SIKP | Definisi field dan periode, role/capability, export versioned, masking data, file privat, signed download, audit; verifikasi sampel terhadap ledger dan format penerima. |
| 8 — rollout | Staging end-to-end dengan callback resmi/provider sandbox, load/concurrency, failover, backup/restore, rekonsiliasi, runbook, feature flags, dan cutover bertahap. Jangan matikan manual path sebelum rekonsiliasi produksi disetujui. |

Dependensi bisnis: voucher dan poin memengaruhi total checkout, sehingga kalkulasinya harus berada di dalam transaksi `create_order` dan diuji bersama stok, biaya shipment, payment amount, pembatalan, dan refund. Ekspor SIKP sebaiknya membaca ledger yang immutable, bukan menghitung ulang dari status UI/order yang dapat berubah.

## 8. Asumsi dan pertanyaan terbuka untuk diputuskan

### Payment gateway

1. Penyedia gateway yang dipilih? Apakah kontraknya menyediakan QRIS dinamis, VA, refund, inquiry status, callback sandbox, dan payout terpisah?
2. Apakah COD tetap tersedia setelah gateway live? Siapa yang menanggung penyetoran dan rekonsiliasi COD?
3. Kapan payment expiry berlaku (sekarang 24 jam pada checkout non-COD), dan bagaimana menangani callback sukses yang datang setelah expiry atau setelah stok dikembalikan?
4. Apakah verifikasi transfer manual tetap menjadi fallback? Perlu bukti upload atau hanya rekonsiliasi rekening terpisah?
5. Fee gateway ditanggung platform, seller, atau buyer; dihitung dari subtotal atau total termasuk ongkir/subsidi?

### Escrow dan seller withdrawal

1. Apakah platform secara legal/operasional bertindak sebagai escrow, dan apakah provider menyediakan split settlement atau dana benar-benar ditahan pada rekening/payment account platform?
2. Dana dilepas setelah konfirmasi buyer, otomatis setelah berapa hari, atau setelah status lain? Bagaimana dispute, retur, refund parsial, chargeback, seller gagal kirim, dan komisi?
3. Perlu saldo available dan pending terpisah? Minimal payout, biaya payout, limit harian, KYC/rekening terverifikasi, jadwal payout, persetujuan dua admin?
4. Siapa menanggung selisih COD, pengembalian uang, dan saldo seller negatif setelah refund/chargeback?

### Pengiriman

1. Penyedia ongkir/agregator apa yang akan dipakai, dan apakah API mendukung quote, pickup, label, tracking, cancel shipment serta webhook sandbox?
2. Satu order multi-seller akan menjadi beberapa waybill? Bagaimana alamat asal, berat volumetrik, paket gabungan, dan biaya per seller dihitung?
3. Apakah seller boleh memilih kurir/layanan yang tidak tersedia dari API dan memasukkan resi manual? Bagaimana label manual dibedakan dari tracking terverifikasi?
4. Apakah status `selesai` tetap memerlukan semua shipment diterima buyer, atau diterapkan auto-complete/dispute window?

### Voucher GBBI

1. Program mensubsidi produk, ongkir, atau kombinasi? Siapa yang mendanai, bagaimana settlement dan cap per transaksi?
2. Kuota dihitung saat claim, order dibayar, atau checkout; berapa batas total, per user, dan periode? Reservasi dilepas kapan?
3. Apakah ada minimum belanja, merchant/produk/wilayah eligible, stacking dengan diskon/poin, dan siapa yang boleh membuat/mengubah program?
4. Bagaimana perlakuan voucher saat order dibatalkan, refund parsial, retur atau penyalahgunaan akun?

### Poin loyalitas

1. Formula earning dan conversion rupiah-per-poin; nilai minimum, maksimum redemption, masa berlaku dan urutan pemakaian?
2. Poin diperoleh pada pembayaran atau penyelesaian barang? Bagaimana COD, pembatalan, retur, refund parsial, dan chargeback?
3. Bolehkah poin digabung dengan voucher subsidi/promo lain, dan apakah nilai poin dihitung sebagai potongan item atau ongkir?

### Ekspor SIKP dan hak akses

1. Apa kepanjangan/kontrak SIKP dalam konteks proyek ini, format file (CSV/XLSX/API), delimiter/encoding, kolom wajib, kode referensi, dan aturan zona waktu/periode?
2. Data agregat atau baris per transaksi? Apakah nomor order, data UMKM, nilai subsidi, fee, pajak, rekening/payout diperlukan? Data personal harus diminimalkan/masking.
3. Pengguna mana yang berhak mengekspor: role baru `super_admin`, capability terpisah, atau admin tertentu? Siapa yang mengesahkan dan mengaudit unduhan?
4. Apakah file diunggah ke endpoint SIKP atau diunduh manual? Berapa retention, batas periode, dan jadwal ekspor?

### Keputusan teknis umum

- Apakah tabel migrasi existing di staging/produksi sudah sama dengan rantai migration repo, terutama skema `payment_methods` dari script setup akar repo?
- Apakah platform satu mata uang IDR saja, dan apakah semua pembulatan harus ke rupiah bulat?
- Apakah dibutuhkan masa retensi webhook/payload, audit, export, serta persyaratan penghapusan data personal?
- Siapa on-call untuk callback tertunda, payout gagal, dan ledger tidak seimbang; bagaimana proses rekonsiliasi manual dan incident response?

## 9. Risiko dan kriteria penerimaan sebelum rilis

- **Dana dan idempotensi:** retry webhook/payout tidak boleh menggandakan paid state, escrow release, atau debit wallet. Buktikan dengan replay event paralel.
- **Kesesuaian nilai:** amount, currency, fee, ongkir, subsidi dan poin ditentukan/diperiksa server; callback mismatch masuk exception queue.
- **Persaingan kuota/saldo:** dua request bersamaan tidak boleh melewati kuota voucher, anggaran, saldo poin, atau saldo seller.
- **Transisi yang tidak sah:** pembayaran terlambat, pembatalan, expired cron, pengiriman parsial multi-seller, refund, dan completion diuji sebagai state machine.
- **Privasi/RLS:** tes buyer vs buyer lain, seller vs seller lain, admin vs Super Admin, anon, dan service role; direct table write harus ditolak.
- **Tidak bocor secret:** pemindaian bundle/build dan repository memastikan secret tidak masuk frontend, log, export, maupun error response.
- **Operasional:** alert callback invalid/tertunda, payout gagal, shipment callback berhenti, ledger tidak balance, dan job export gagal; tersedia cara retry/reconcile yang aman.
- **Cutover:** staging membuktikan kontrak gateway dan kurir provider; rekonsiliasi manual-vs-provider dilakukan sebelum manual payment verification dinonaktifkan.

