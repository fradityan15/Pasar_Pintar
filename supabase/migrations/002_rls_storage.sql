-- PasarPintar · 002 · Keamanan (Row Level Security) dan Storage

-- Cek admin di sisi database; tidak bisa dipalsukan dari browser.
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;
grant execute on function public.is_admin() to anon, authenticated;

alter table public.profiles          enable row level security;
alter table public.addresses         enable row level security;
alter table public.regions           enable row level security;
alter table public.categories        enable row level security;
alter table public.umkm              enable row level security;
alter table public.products          enable row level security;
alter table public.product_images    enable row level security;
alter table public.cart_items        enable row level security;
alter table public.orders            enable row level security;
alter table public.order_items       enable row level security;
alter table public.order_status_logs enable row level security;
alter table public.stock_movements   enable row level security;

-- ───────── profiles ─────────
create policy profiles_select on public.profiles for select to authenticated
  using (id = (select auth.uid()) or public.is_admin());
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));
-- Pelanggan hanya boleh mengubah nama & telepon; kolom role tidak bisa disentuh.
revoke insert, update, delete on public.profiles from anon, authenticated;
grant update (full_name, phone) on public.profiles to authenticated;

-- ───────── addresses & cart_items (milik sendiri) ─────────
create policy addresses_own on public.addresses for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy addresses_admin_read on public.addresses for select to authenticated
  using (public.is_admin());

create policy cart_own on public.cart_items for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- ───────── katalog: publik membaca yang aktif, admin mengelola ─────────
create policy regions_read on public.regions for select to anon, authenticated using (true);
create policy categories_read on public.categories for select to anon, authenticated
  using (is_active or public.is_admin());
create policy umkm_read on public.umkm for select to anon, authenticated
  using (is_active or public.is_admin());
create policy products_read on public.products for select to anon, authenticated
  using (is_active or public.is_admin());
create policy product_images_read on public.product_images for select to anon, authenticated
  using (exists (select 1 from public.products p where p.id = product_id and (p.is_active or public.is_admin())));

create policy regions_admin    on public.regions        for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy categories_admin on public.categories    for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy umkm_admin       on public.umkm          for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy products_admin   on public.products      for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy images_admin     on public.product_images for all to authenticated using (public.is_admin()) with check (public.is_admin());

revoke insert, update, delete on public.regions, public.categories, public.umkm,
  public.products, public.product_images from anon;

-- ───────── pesanan: hanya dibaca; perubahan lewat fungsi (003) ─────────
create policy orders_read on public.orders for select to authenticated
  using (user_id = (select auth.uid()) or public.is_admin());
create policy order_items_read on public.order_items for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id
                 and (o.user_id = (select auth.uid()) or public.is_admin())));
create policy order_logs_read on public.order_status_logs for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id
                 and (o.user_id = (select auth.uid()) or public.is_admin())));
create policy stock_admin_read on public.stock_movements for select to authenticated
  using (public.is_admin());

revoke insert, update, delete on public.orders, public.order_items,
  public.order_status_logs, public.stock_movements from anon, authenticated;
revoke all on public.profiles, public.addresses, public.cart_items, public.orders,
  public.order_items, public.order_status_logs, public.stock_movements from anon;

-- ───────── Storage: gambar produk (baca publik, tulis admin) ─────────
insert into storage.buckets (id, name, public)
values ('product-images', 'product-images', true)
on conflict (id) do nothing;

create policy "gambar produk dibaca publik" on storage.objects for select
  using (bucket_id = 'product-images');
create policy "admin kelola gambar produk" on storage.objects for all to authenticated
  using (bucket_id = 'product-images' and public.is_admin())
  with check (bucket_id = 'product-images' and public.is_admin());
