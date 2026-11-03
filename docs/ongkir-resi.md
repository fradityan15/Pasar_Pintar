# Tarif ongkir, wilayah, dan resi RajaOngkir

Pencarian wilayah dan tarif domestik menggunakan API RajaOngkir Komerce dari Supabase Edge Functions. API key hanya dibaca di server. Tidak ada tarif, ID wilayah, atau jawaban mock di frontend.

## Konfigurasi

Atur key pada project Supabase yang digunakan:

```sh
npx supabase secrets set RAJAONGKIR_API_KEY=YOUR_API_KEY
```

Jangan menyimpan key di source code, `.env` frontend, atau variabel `VITE_`. Migration `036_rajaongkir_shipping.sql` menambahkan `addresses.rajaongkir_area_id` dan `umkm.rajaongkir_origin_area_id`. Migration itu juga menjaga kolom lama yang dibaca RPC checkout (`biteship_area_id` dan `biteship_origin_area_id`) tetap sinkron dari kolom RajaOngkir saat alamat atau pengaturan toko disimpan. ID dari provider lama tidak disalin karena ID provider berbeda.

Deploy fungsi setelah migration diterapkan:

```sh
npx supabase functions deploy search-rajaongkir-areas
npx supabase functions deploy rajaongkir-rates
npx supabase functions deploy shipping-track
```

## Pemilihan wilayah

Komponen `RajaOngkirAreaPicker` memanggil fungsi `search-rajaongkir-areas` setelah pengguna mengetik minimal dua karakter. Pengguna dapat mencari dengan kode pos atau nama wilayah; jika nama diawali kata seperti "Kecamatan" atau "Kabupaten", fungsi juga mencoba pencarian tanpa awalan tersebut. Fungsi meminta direktori domestic destination, lalu menyimpan ID hasil yang dipilih ke alamat atau pengaturan lokasi toko. Mengubah teks pencarian membatalkan ID terpilih; alamat dan lokasi asal toko tidak dapat disimpan tanpa memilih hasil resmi.

## Tarif checkout

Checkout memanggil `rajaongkir-rates` dengan ID alamat dan produk yang dipilih. Fungsi memeriksa identitas pengguna, kepemilikan alamat, isi keranjang, ketersediaan produk/toko, berat, wilayah asal dan tujuan, serta kurir yang diaktifkan toko. Tarif diminta per toko/kurir. Quote disimpan di server selama 10 menit dan RPC `create_order` memvalidasi quote sebelum membuat pesanan.

Penjual mengisi berat tiap produk dalam gram melalui halaman **Produk Saya**. Produk dengan berat kosong atau nol tidak dapat dipakai untuk meminta tarif.

Kegagalan provider, area yang tidak dikenal, berat kosong, atau tidak ada layanan menghasilkan error yang dapat ditindaklanjuti; sistem tidak menggantinya dengan harga statis. `create_order` lama tetap memeriksa kolom area internal Biteship, yang disinkronkan oleh trigger dalam migration 036. Data area Biteship lama tidak dapat digunakan sebagai area RajaOngkir; pelanggan dan seller perlu memilih ulang wilayah.

## Resi dan pelacakan

Seller memasukkan kurir dan nomor resi ketika menandai pesanan dikirim. Validasi dan penyimpanan resi tetap menggunakan RPC order yang ada. Integrasi RajaOngkir yang ditambahkan saat ini mencakup pencarian wilayah dan tarif, bukan API pelacakan. Fungsi `shipping-track` hanya mengembalikan event pelacakan yang sudah tersimpan dan menjelaskan bahwa pelacakan otomatis provider belum tersedia.

Untuk presentasi, halaman pesanan penjual menyediakan **Isi resi demo** dengan nomor berawalan `DEMO-`. Setelah dikirim, event simulasi terlihat pada detail pesanan pembeli; nomor demo tidak dapat dilacak di kurir sungguhan. Migration `037_seller_shipping_status_sync.sql` menyelaraskan status utama pesanan saat toko mengirim, sambil tetap mensyaratkan item berstatus diproses dan pembayaran lunas atau COD.

## Batas verifikasi

Implementasi menargetkan endpoint Komerce `GET /api/v1/destination/domestic-destination` dan `POST /api/v1/calculate/domestic-cost`, memakai header `key` dan field `origin`, `destination`, `weight`, `courier`, serta `price=lowest` untuk tarif domestik. Dukungan kurir tetap bergantung pada paket dan akun RajaOngkir yang dipakai.
