# Chat penjual dan admin

Migration `supabase/migrations/041_seller_admin_chat.sql` menambahkan percakapan per toko. Penjual dapat memulai laporan dari menu **Chat Admin** di dashboard penjual. Admin melihat dan membalas pesan melalui menu **Pesan Penjual**.

Pesan disimpan di database, dibatasi 2.000 karakter, dan diperbarui otomatis saat halaman terbuka. Akses database diberikan hanya melalui RPC yang memeriksa pemilik toko atau role admin; tabel pesan tidak dapat dibaca atau ditulis langsung oleh klien.

Terapkan migration di project Supabase yang digunakan aplikasi, lalu deploy frontend agar menu dan halaman chat tersedia.
