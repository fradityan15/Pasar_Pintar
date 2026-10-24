-- PasarPintar · 003 · Fungsi (RPC): checkout, pesanan, stok, peran, laporan
-- Semua perubahan pesanan/stok lewat fungsi ini agar atomik dan tidak bisa dimanipulasi dari browser.

-- Pengembalian stok (internal, tidak diekspos ke API)
create or replace function private.restock_order(p_order_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in select product_id, quantity from public.order_items
           where order_id = p_order_id and product_id is not null order by product_id loop
    update public.products set stock = stock + r.quantity where id = r.product_id;
    insert into public.stock_movements (product_id, change, reason, order_id, created_by)
    values (r.product_id, r.quantity, p_reason, p_order_id, auth.uid());
  end loop;
end $$;

-- ───────── Checkout ─────────
-- Memeriksa stok, membuat pesanan, mengurangi stok, mengosongkan keranjang, dalam satu transaksi.
create or replace function public.create_order(p_address_id uuid, p_payment_method text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_uid       uuid := auth.uid();
  v_addr      public.addresses%rowtype;
  v_order_id  uuid;
  v_subtotal  numeric := 0;
  v_shipping  numeric := 15000;   -- tarif pengiriman standar PasarPintar
  r           record;
begin
  if v_uid is null then raise exception 'Silakan login terlebih dahulu'; end if;
  if p_payment_method not in ('qris', 'virtual_account') then
    raise exception 'Metode pembayaran tidak valid';
  end if;

  select * into v_addr from public.addresses where id = p_address_id and user_id = v_uid;
  if not found then raise exception 'Alamat tidak ditemukan'; end if;
  if not exists (select 1 from public.cart_items where user_id = v_uid) then
    raise exception 'Keranjang kosong';
  end if;

  -- Kunci baris produk (urut id agar tidak deadlock) lalu validasi stok.
  for r in
    select p.id, p.name, p.price, p.stock, p.is_active, c.quantity
    from public.cart_items c join public.products p on p.id = c.product_id
    where c.user_id = v_uid order by p.id for update of p
  loop
    if not r.is_active then raise exception 'Produk "%" tidak tersedia', r.name; end if;
    if r.stock < r.quantity then
      raise exception 'Stok "%" tidak cukup (tersisa %)', r.name, r.stock;
    end if;
    v_subtotal := v_subtotal + r.price * r.quantity;
  end loop;

  insert into public.orders (user_id, payment_method, subtotal, shipping_cost, total,
                             shipping_address, payment_expires_at)
  values (v_uid, p_payment_method, v_subtotal, v_shipping, v_subtotal + v_shipping,
          to_jsonb(v_addr) - 'id' - 'user_id' - 'created_at' - 'is_default',
          now() + interval '24 hours')
  returning id into v_order_id;

  for r in
    select p.id, p.name, p.price, p.umkm_id, c.quantity
    from public.cart_items c join public.products p on p.id = c.product_id
    where c.user_id = v_uid order by p.id
  loop
    insert into public.order_items (order_id, product_id, umkm_id, product_name, unit_price, quantity)
    values (v_order_id, r.id, r.umkm_id, r.name, r.price, r.quantity);
    update public.products set stock = stock - r.quantity where id = r.id;
    insert into public.stock_movements (product_id, change, reason, order_id, created_by)
    values (r.id, -r.quantity, 'pesanan', v_order_id, v_uid);
  end loop;

  insert into public.order_status_logs (order_id, status, changed_by, note)
  values (v_order_id, 'menunggu_pembayaran', v_uid, 'Pesanan dibuat');

  delete from public.cart_items where user_id = v_uid;
  return v_order_id;
end $$;

-- ───────── Pembatalan ─────────
-- Pelanggan: hanya saat menunggu pembayaran. Admin: saat menunggu pembayaran atau diproses.
create or replace function public.cancel_order(p_order_id uuid, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v public.orders%rowtype;
begin
  select * into v from public.orders where id = p_order_id for update;
  if not found or (v.user_id <> auth.uid() and not public.is_admin()) then
    raise exception 'Pesanan tidak ditemukan';
  end if;
  if not (v.status = 'menunggu_pembayaran' or (v.status = 'diproses' and public.is_admin())) then
    raise exception 'Pesanan tidak dapat dibatalkan pada status ini';
  end if;

  update public.orders set status = 'dibatalkan' where id = p_order_id;
  perform private.restock_order(p_order_id, 'pesanan dibatalkan');
  insert into public.order_status_logs (order_id, status, changed_by, note)
  values (p_order_id, 'dibatalkan', auth.uid(), coalesce(p_reason, 'Dibatalkan'));
end $$;

-- Pesanan belum dibayar yang lewat batas waktu dibatalkan otomatis.
-- Jadwalkan dengan pg_cron (lihat panduan) atau panggil manual dari admin.
create or replace function public.expire_unpaid_orders()
returns integer language plpgsql security definer set search_path = public as $$
declare r record; n integer := 0;
begin
  if auth.uid() is not null and not public.is_admin() then raise exception 'Akses ditolak'; end if;
  for r in select id from public.orders
           where status = 'menunggu_pembayaran' and payment_expires_at < now() for update loop
    update public.orders set status = 'dibatalkan', payment_status = 'kedaluwarsa' where id = r.id;
    perform private.restock_order(r.id, 'pembayaran kedaluwarsa');
    insert into public.order_status_logs (order_id, status, note)
    values (r.id, 'dibatalkan', 'Pembayaran kedaluwarsa');
    n := n + 1;
  end loop;
  return n;
end $$;

-- ───────── Admin ─────────
create or replace function public.admin_update_order_status(p_order_id uuid, p_status public.order_status, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v public.orders%rowtype;
begin
  if not public.is_admin() then raise exception 'Akses ditolak'; end if;
  select * into v from public.orders where id = p_order_id for update;
  if not found then raise exception 'Pesanan tidak ditemukan'; end if;
  if not ((v.status = 'diproses' and p_status = 'dikirim') or (v.status = 'dikirim' and p_status = 'selesai')) then
    raise exception 'Perubahan status % → % tidak diizinkan', v.status, p_status;
  end if;
  update public.orders set status = p_status where id = p_order_id;
  insert into public.order_status_logs (order_id, status, changed_by, note)
  values (p_order_id, p_status, auth.uid(), p_note);
end $$;

create or replace function public.admin_set_user_role(p_user_id uuid, p_role public.user_role)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Akses ditolak'; end if;
  if p_user_id = auth.uid() and p_role <> 'admin' then
    raise exception 'Anda tidak dapat menurunkan peran akun sendiri';
  end if;
  update public.profiles set role = p_role where id = p_user_id;
end $$;

create or replace function public.admin_adjust_stock(p_product_id uuid, p_change integer, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Akses ditolak'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'Alasan wajib diisi'; end if;
  update public.products set stock = stock + p_change where id = p_product_id;  -- stok < 0 ditolak CHECK
  if not found then raise exception 'Produk tidak ditemukan'; end if;
  insert into public.stock_movements (product_id, change, reason, created_by)
  values (p_product_id, p_change, p_reason, auth.uid());
end $$;

-- ───────── Dashboard & laporan ─────────
create or replace function public.dashboard_stats()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Akses ditolak'; end if;
  return jsonb_build_object(
    'total_produk',        (select count(*) from public.products),
    'pesanan_selesai',     (select count(*) from public.orders where status = 'selesai'),
    'pesanan_dibatalkan',  (select count(*) from public.orders where status = 'dibatalkan'),
    'umkm_aktif',          (select count(*) from public.umkm where is_active),
    'menunggu_pembayaran', (select count(*) from public.orders where status = 'menunggu_pembayaran'),
    'stok_menipis',        (select count(*) from public.products where is_active and stock <= 10),
    'umkm_belum_verifikasi', (select count(*) from public.umkm where not is_verified),
    'omzet_7_hari',        coalesce((select sum(total) from public.orders
                             where payment_status = 'dibayar' and status <> 'dibatalkan'
                               and created_at >= now() - interval '7 days'), 0));
end $$;

create or replace function public.sales_report(p_from date, p_to date)
returns table (tanggal date, jumlah_pesanan bigint, omzet numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Akses ditolak'; end if;
  return query
    select d::date, count(o.id), coalesce(sum(o.total), 0)
    from generate_series(p_from, p_to, interval '1 day') d
    left join public.orders o
      on (o.created_at at time zone 'Asia/Jakarta')::date = d::date
     and o.payment_status = 'dibayar' and o.status <> 'dibatalkan'
    group by d order by d;
end $$;

-- ───────── Hak eksekusi: hanya pengguna login ─────────
revoke execute on function
  public.create_order(uuid, text),
  public.cancel_order(uuid, text), public.expire_unpaid_orders(),
  public.admin_update_order_status(uuid, public.order_status, text),
  public.admin_set_user_role(uuid, public.user_role),
  public.admin_adjust_stock(uuid, integer, text),
  public.dashboard_stats(), public.sales_report(date, date)
from public, anon;
grant execute on function
  public.create_order(uuid, text),
  public.cancel_order(uuid, text), public.expire_unpaid_orders(),
  public.admin_update_order_status(uuid, public.order_status, text),
  public.admin_set_user_role(uuid, public.user_role),
  public.admin_adjust_stock(uuid, integer, text),
  public.dashboard_stats(), public.sales_report(date, date)
to authenticated;
