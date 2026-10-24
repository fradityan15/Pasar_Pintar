# Panduan deploy PasarPintar (Vercel + Supabase)

Hasil akhirnya: website bisa dibuka lewat link `https://nama-anda.vercel.app`. Gratis untuk skala demo.

## 0. Cek dulu di komputer
1. `npm run build` harus selesai tanpa error (muncul folder `dist`).
2. Pastikan file `.env` TIDAK ikut ke Git (sudah ada di `.gitignore`).
3. Jika pernah menjalankan seed versi lama, jalankan ulang `supabase/seed.sql` untuk menghapus produk/UMKM demo berdasarkan slug khusus. Data UMKM dan produk baru dimasukkan melalui pendaftaran atau panel admin/penjual.
4. Pastikan ada minimal satu akun admin.

## 1. Unggah kode ke GitHub
1. Pasang Git (git-scm.com) dan buat akun di github.com.
2. Di github.com klik **New repository** → nama `pasarpintar` → **Private** → Create (jangan centang README).
3. Di terminal, di folder proyek:
   ```
   git init
   git add .
   git commit -m "PasarPintar"
   git branch -M main
   git remote add origin https://github.com/USERNAME/pasarpintar.git
   git push -u origin main
   ```
4. Buka repository di browser. File `.env` tidak boleh terlihat di sana.

## 2. Deploy di Vercel
1. Buka vercel.com → **Sign Up** → **Continue with GitHub**.
2. **Add New → Project** → pilih repository `pasarpintar` → **Import**.
3. Framework Preset: **Vite** (terdeteksi otomatis). Build Command `npm run build`, Output Directory `dist`.
4. Buka **Environment Variables**, tambahkan dua variabel:
   - `VITE_SUPABASE_URL` = Project URL dari Supabase
   - `VITE_SUPABASE_ANON_KEY` = anon public key (BUKAN service_role key)
5. Klik **Deploy**. Tunggu 1–2 menit sampai muncul link `https://xxxx.vercel.app`.

## 3. Hubungkan Supabase dengan alamat baru (wajib)
Di Supabase: **Authentication → URL Configuration**
- **Site URL**: isi link Vercel Anda.
- **Redirect URLs**: tambahkan `https://xxxx.vercel.app/**` dan `http://localhost:5173/**`.

Tanpa langkah ini, tautan verifikasi email dan reset kata sandi mengarah ke alamat yang salah.

## 4. Verifikasi email
- Untuk demo, "Confirm email" boleh tetap nonaktif supaya pendaftaran langsung bisa masuk.
- Jika diaktifkan untuk pemakaian nyata, siapkan SMTP sendiri (Authentication → SMTP Settings); pengirim email bawaan Supabase sangat dibatasi jumlahnya.

## 5. Tes cepat setelah deploy (5 menit)
1. Buka link Vercel: beranda dan produk tampil (termasuk foto).
2. Buka `/katalog`, tekan **refresh**: halaman tetap tampil, tidak 404.
3. Daftar akun baru lalu masuk.
4. Tambah produk ke keranjang → checkout → pastikan pesanan tercatat dengan status menunggu pembayaran. Transaksi pembayaran memerlukan payment gateway dan webhook terverifikasi.
5. Masuk sebagai admin: `/admin/ringkasan` terbuka, ubah status pesanan menjadi Dikirim.
6. Buka link dari HP: tampilan tidak melebar ke samping.

## 6. Memperbarui website & rollback
- Setiap `git push` ke branch `main` otomatis membuat deploy baru.
- Jika deploy baru bermasalah: Vercel → **Deployments** → pilih deploy lama yang sehat → **⋯ → Promote to Production** (atau Instant Rollback).

## 7. Domain sendiri (opsional)
Vercel → Project → **Settings → Domains** → tambah domain, lalu ikuti petunjuk DNS di layar. Setelah itu, perbarui Site URL dan Redirect URLs di Supabase (langkah 3).

## 8. Checklist keamanan
- [ ] Hanya `anon key` yang dipakai di Vercel dan kode. `service_role key` tidak pernah dipakai.
- [ ] Table Editor tidak menampilkan label "Unrestricted" pada tabel mana pun (RLS aktif).
- [ ] Bucket `product-images` ada dan hanya admin yang bisa menulis.
- [ ] Jumlah akun admin minimal, dan password admin kuat.
- [ ] Repository GitHub berstatus Private dan tanpa file `.env`.
- [ ] Jadwal pembatalan pesanan kedaluwarsa (004_cron.sql) aktif, atau dijalankan manual dari admin.

## 9. Jika ada masalah
| Gejala | Penyebab umum | Solusi |
|---|---|---|
| Halaman putih setelah deploy | Environment variable belum diisi | Isi dua variabel di Vercel → **Redeploy** (nilai tertanam saat build) |
| 404 saat refresh `/katalog` | Aturan SPA tidak terbaca | Pastikan `vercel.json` ada di root repo, lalu deploy ulang |
| Setelah login diarahkan ke `localhost` | Site URL Supabase belum diganti | Ulangi langkah 3 |
| Foto tidak tampil | Bucket tidak publik atau URL salah | Cek bucket `product-images` publik di Storage |
| "permission denied" / data kosong | RLS memblokir | Cek apakah akun sudah login dan perannya benar |

## Alternatif: Netlify
New site from Git → pilih repo → Build command `npm run build`, Publish directory `dist` → isi dua environment variable yang sama → Deploy. File `public/_redirects` sudah menangani refresh rute.
