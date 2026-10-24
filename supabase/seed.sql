-- PasarPintar · seed untuk data referensi kategori dan daerah.
-- Data produk dan UMKM harus berasal dari pendaftaran atau input admin/penjual.

-- Bersihkan data demo dari versi seed sebelumnya berdasarkan slug yang spesifik.
delete from public.products
where slug in (
  'kopi-arabika-250g',
  'kopi-robusta-250g',
  'keripik-pisang-manis',
  'keripik-singkong-pedas',
  'dodol-garut',
  'jamu-kunyit-asam'
);

delete from public.umkm
where slug in (
  'contoh-umkm-kopi-gayo',
  'contoh-umkm-keripik-lampung',
  'contoh-umkm-dodol-garut'
);

insert into public.regions (name, province) values
  ('Dataran Tinggi Gayo', 'Aceh'),
  ('Lampung Barat', 'Lampung'),
  ('Pangalengan', 'Jawa Barat'),
  ('Garut', 'Jawa Barat'),
  ('Ende', 'Nusa Tenggara Timur'),
  ('Kuala Pembuang', 'Kalimantan Tengah')
on conflict do nothing;

insert into public.categories (name, slug) values
  ('Makanan Ringan', 'makanan-ringan'),
  ('Kopi & Teh', 'kopi-teh'),
  ('Kerajinan', 'kerajinan'),
  ('Batik & Tenun', 'batik-tenun'),
  ('Herbal & Jamu', 'herbal-jamu'),
  ('Oleh-oleh', 'oleh-oleh')
on conflict do nothing;

insert into public.categories (parent_id, name, slug)
select id, 'Keripik', 'keripik' from public.categories where slug = 'makanan-ringan'
on conflict do nothing;
