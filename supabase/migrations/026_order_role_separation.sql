create or replace function public.seller_owns_order(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.order_items oi
    where oi.order_id = p_order_id
      and public.owns_active_umkm(oi.umkm_id)
  );
$$;

revoke all on function public.seller_owns_order(uuid) from public, anon;
grant execute on function public.seller_owns_order(uuid) to authenticated;

drop policy if exists orders_seller_read on public.orders;
create policy orders_seller_read on public.orders
  for select to authenticated
  using (public.seller_owns_order(id));

drop policy if exists orders_seller_update on public.orders;
create policy orders_seller_update on public.orders
  for update to authenticated
  using (
    public.seller_owns_order(id)
    and status in ('menunggu_diproses', 'diproses')
  )
  with check (
    public.seller_owns_order(id)
    and status in ('menunggu_diproses', 'diproses', 'dikirim')
  );

create or replace function public.create_order(
  p_address_id uuid,
  p_payment_method_id uuid,
  p_product_ids uuid[],
  p_shipping_method text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_addr public.addresses%rowtype;
  v_order_id uuid;
  v_product_ids uuid[];
  v_payment_category text;
  v_initial_status public.order_status;
  v_cart_count bigint;
  v_subtotal numeric := 0;
  v_shipping numeric;
  r record;
begin
  if v_uid is null then
    raise exception 'Silakan login terlebih dahulu';
  end if;

  select pm.category
  into v_payment_category
  from public.payment_methods pm
  where pm.id = p_payment_method_id
    and pm.is_active
  for share;

  if not found then
    raise exception 'Metode pembayaran tidak ditemukan atau tidak aktif';
  end if;

  v_initial_status := case
    when v_payment_category = 'cod' then 'menunggu_diproses'::public.order_status
    else 'menunggu_pembayaran'::public.order_status
  end;

  v_shipping := case p_shipping_method
    when 'regular' then 15000
    when 'economy' then 10000
    else null
  end;
  if v_shipping is null then
    raise exception 'Metode pengiriman tidak valid';
  end if;

  select *
  into v_addr
  from public.addresses
  where id = p_address_id
    and user_id = v_uid;
  if not found then
    raise exception 'Alamat tidak ditemukan';
  end if;

  if p_product_ids is null then
    select array_agg(product_id)
    into v_product_ids
    from public.cart_items
    where user_id = v_uid;
  else
    v_product_ids := p_product_ids;
  end if;

  if coalesce(cardinality(v_product_ids), 0) = 0 then
    raise exception 'Keranjang kosong';
  end if;

  select count(distinct product_id)
  into v_cart_count
  from public.cart_items
  where user_id = v_uid
    and product_id = any(v_product_ids);
  if v_cart_count <> cardinality(v_product_ids) then
    raise exception 'Sebagian produk pilihan tidak lagi tersedia di keranjang';
  end if;

  for r in
    select p.id, p.name, p.price, p.stock, p.is_active, c.quantity
    from public.cart_items c
    join public.products p on p.id = c.product_id
    where c.user_id = v_uid
      and c.product_id = any(v_product_ids)
    order by p.id
    for update of p
  loop
    if not r.is_active then
      raise exception 'Produk "%" tidak tersedia', r.name;
    end if;
    if r.stock < r.quantity then
      raise exception 'Stok "%" tidak cukup (tersisa %)', r.name, r.stock;
    end if;
    v_subtotal := v_subtotal + r.price * r.quantity;
  end loop;

  insert into public.orders (
    user_id,
    payment_method_id,
    shipping_method,
    subtotal,
    shipping_cost,
    total,
    shipping_address,
    payment_expires_at,
    status
  )
  values (
    v_uid,
    p_payment_method_id,
    p_shipping_method,
    v_subtotal,
    v_shipping,
    v_subtotal + v_shipping,
    to_jsonb(v_addr) - 'id' - 'user_id' - 'created_at' - 'is_default',
    case when v_payment_category = 'cod' then null else now() + interval '24 hours' end,
    v_initial_status
  )
  returning id into v_order_id;

  for r in
    select p.id, p.name, p.price, p.umkm_id, c.quantity
    from public.cart_items c
    join public.products p on p.id = c.product_id
    where c.user_id = v_uid
      and c.product_id = any(v_product_ids)
    order by p.id
  loop
    insert into public.order_items (
      order_id,
      product_id,
      umkm_id,
      product_name,
      unit_price,
      quantity
    )
    values (
      v_order_id,
      r.id,
      r.umkm_id,
      r.name,
      r.price,
      r.quantity
    );

    update public.products
    set stock = stock - r.quantity
    where id = r.id;

    insert into public.stock_movements (product_id, change, reason, order_id, created_by)
    values (r.id, -r.quantity, 'pesanan', v_order_id, v_uid);
  end loop;

  insert into public.order_status_logs (order_id, status, changed_by, note)
  values (
    v_order_id,
    v_initial_status,
    v_uid,
    case when v_payment_category = 'cod' then 'Pesanan COD dibuat' else 'Pesanan dibuat' end
  );

  delete from public.cart_items
  where user_id = v_uid
    and product_id = any(v_product_ids);

  return v_order_id;
end;
$$;

revoke all on function public.create_order(uuid, uuid, uuid[], text) from public, anon;
grant execute on function public.create_order(uuid, uuid, uuid[], text) to authenticated;

drop function public.seller_list_orders(uuid);
create function public.seller_list_orders(p_umkm_id uuid)
returns table (
  order_id uuid,
  order_no text,
  customer_name text,
  products jsonb,
  total numeric,
  status public.order_status,
  seller_shipping_status text,
  payment_status text,
  payment_category text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.owns_active_umkm(p_umkm_id) then
    raise exception 'Akses ditolak';
  end if;

  return query
  select
    o.id,
    o.order_no,
    coalesce(p.full_name, 'Pembeli'),
    jsonb_agg(
      jsonb_build_object(
        'product_name', oi.product_name,
        'quantity', oi.quantity,
        'unit_price', oi.unit_price
      ) order by oi.id
    ),
    sum(oi.unit_price * oi.quantity),
    o.status,
    case
      when bool_and(oi.seller_shipping_status = 'dikirim') then 'dikirim'
      when bool_or(oi.seller_shipping_status = 'diproses') then 'diproses'
      else 'menunggu_diproses'
    end,
    o.payment_status,
    coalesce(pm.category, case when o.payment_method = 'cod' then 'cod' end),
    o.created_at
  from public.orders o
  join public.order_items oi on oi.order_id = o.id and oi.umkm_id = p_umkm_id
  left join public.profiles p on p.id = o.user_id
  left join public.payment_methods pm on pm.id = o.payment_method_id
  group by o.id, p.full_name, pm.category
  order by o.created_at desc;
end;
$$;

revoke all on function public.seller_list_orders(uuid) from public, anon;
grant execute on function public.seller_list_orders(uuid) to authenticated;

with converted_cod_orders as (
  update public.orders o
  set status = 'menunggu_diproses'
  from public.payment_methods pm
  where pm.id = o.payment_method_id
    and pm.category = 'cod'
    and o.status = 'menunggu_pembayaran'
  returning o.id
)
insert into public.order_status_logs (order_id, status, note)
select id, 'menunggu_diproses', 'Pesanan COD siap diproses penjual'
from converted_cod_orders;

create or replace function public.admin_confirm_order_payment(
  p_order_id uuid,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_payment_category text;
begin
  if not public.is_admin() then
    raise exception 'Akses ditolak';
  end if;

  select *
  into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Pesanan tidak ditemukan';
  end if;

  if v_order.status <> 'menunggu_pembayaran'
    or v_order.payment_status not in ('pending', 'belum_dibayar') then
    raise exception 'Pesanan ini tidak sedang menunggu pembayaran';
  end if;

  if v_order.payment_expires_at is not null and v_order.payment_expires_at <= now() then
    raise exception 'Batas waktu pembayaran telah berakhir';
  end if;

  select category
  into v_payment_category
  from public.payment_methods
  where id = v_order.payment_method_id;

  v_payment_category := coalesce(
    v_payment_category,
    case
      when v_order.payment_method = 'cod' then 'cod'
      when v_order.payment_method = 'qris' then 'qris'
      when v_order.payment_method in ('virtual_account', 'va-bca', 'va-mandiri', 'va-bri', 'va-bni', 'bank_transfer') then 'bank_transfer'
    end
  );
  if coalesce(v_payment_category, '') not in ('qris', 'va', 'bank_transfer') then
    raise exception 'Metode pembayaran ini tidak dapat diverifikasi sebagai transfer';
  end if;

  update public.orders
  set payment_status = 'dibayar',
      status = 'menunggu_diproses',
      paid_at = coalesce(paid_at, now())
  where id = p_order_id;

  insert into public.order_status_logs (order_id, status, changed_by, note)
  values (
    p_order_id,
    'menunggu_diproses',
    auth.uid(),
    coalesce(nullif(trim(p_note), ''), 'Pembayaran diverifikasi admin; menunggu penjual')
  );
end;
$$;

revoke all on function public.admin_confirm_order_payment(uuid, text) from public, anon;
grant execute on function public.admin_confirm_order_payment(uuid, text) to authenticated;

drop function if exists public.simulate_payment_confirmation(uuid);

create or replace function public.seller_process_order(p_order_id uuid, p_umkm_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_payment_category text;
begin
  if not public.owns_active_umkm(p_umkm_id) then
    raise exception 'Akses ditolak';
  end if;

  select *
  into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Pesanan tidak tersedia untuk diproses';
  end if;

  select coalesce(pm.category, case when v_order.payment_method = 'cod' then 'cod' end)
  into v_payment_category
  from (select 1) as singleton
  left join public.payment_methods pm on pm.id = v_order.payment_method_id;
  v_payment_category := coalesce(v_payment_category, '');

  if v_order.status not in ('menunggu_diproses', 'diproses')
    or (v_order.payment_status <> 'dibayar' and v_payment_category <> 'cod') then
    raise exception 'Pesanan tidak tersedia untuk diproses';
  end if;

  update public.order_items
  set seller_shipping_status = 'diproses'
  where order_id = p_order_id
    and umkm_id = p_umkm_id
    and seller_shipping_status = 'menunggu_diproses';

  if not found then
    raise exception 'Pesanan tidak tersedia untuk diproses';
  end if;

  if v_order.status = 'menunggu_diproses' then
    update public.orders
    set status = 'diproses'
    where id = p_order_id;
  end if;

  insert into public.order_status_logs (order_id, status, changed_by, note)
  values (p_order_id, 'diproses', auth.uid(), 'Pesanan sedang dikemas oleh toko');
end;
$$;

create or replace function public.seller_ship_order(p_order_id uuid, p_umkm_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_payment_category text;
  v_all_shipped boolean;
begin
  if not public.owns_active_umkm(p_umkm_id) then
    raise exception 'Akses ditolak';
  end if;

  select *
  into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found or v_order.status <> 'diproses' then
    raise exception 'Pesanan tidak tersedia untuk dikirim';
  end if;

  select coalesce(pm.category, case when v_order.payment_method = 'cod' then 'cod' end)
  into v_payment_category
  from (select 1) as singleton
  left join public.payment_methods pm on pm.id = v_order.payment_method_id;
  v_payment_category := coalesce(v_payment_category, '');

  if v_order.payment_status <> 'dibayar' and v_payment_category <> 'cod' then
    raise exception 'Pembayaran pesanan belum dikonfirmasi';
  end if;

  update public.order_items
  set seller_shipping_status = 'dikirim'
  where order_id = p_order_id
    and umkm_id = p_umkm_id
    and seller_shipping_status = 'diproses';

  if not found then
    raise exception 'Pesanan tidak tersedia untuk dikirim';
  end if;

  select not exists (
    select 1
    from public.order_items
    where order_id = p_order_id
      and seller_shipping_status <> 'dikirim'
  )
  into v_all_shipped;

  if v_all_shipped then
    update public.orders
    set status = 'dikirim'
    where id = p_order_id
      and status = 'diproses';

    insert into public.order_status_logs (order_id, status, changed_by, note)
    values (p_order_id, 'dikirim', auth.uid(), 'Seluruh mitra telah mengirim barang');
  else
    insert into public.order_status_logs (order_id, status, changed_by, note)
    values (p_order_id, 'diproses', auth.uid(), 'Pesanan telah diserahkan ke kurir oleh toko');
  end if;
end;
$$;

revoke all on function public.seller_process_order(uuid, uuid) from public, anon;
revoke all on function public.seller_ship_order(uuid, uuid) from public, anon;
grant execute on function public.seller_process_order(uuid, uuid) to authenticated;
grant execute on function public.seller_ship_order(uuid, uuid) to authenticated;

create or replace function public.cancel_order(p_order_id uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
begin
  select *
  into v_order
  from public.orders
  where id = p_order_id
  for update;

  if auth.uid() is null or not found or v_order.user_id <> auth.uid() or public.is_admin() then
    raise exception 'Pesanan tidak ditemukan';
  end if;

  if not (
    v_order.status = 'menunggu_pembayaran'
    or (
      v_order.status in ('menunggu_diproses', 'diproses')
      and exists (
        select 1
        from public.order_items
        where order_id = p_order_id
      )
      and not exists (
        select 1
        from public.order_items
        where order_id = p_order_id
          and seller_shipping_status <> 'menunggu_diproses'
      )
    )
  ) then
    raise exception 'Pesanan tidak dapat dibatalkan pada status ini';
  end if;

  update public.orders
  set status = 'dibatalkan'
  where id = p_order_id;

  perform private.restock_order(p_order_id, 'pesanan dibatalkan');

  insert into public.order_status_logs (order_id, status, changed_by, note)
  values (p_order_id, 'dibatalkan', auth.uid(), coalesce(p_reason, 'Pesanan dibatalkan oleh pembeli'));
end;
$$;

revoke all on function public.admin_update_order_status(uuid, public.order_status, text) from public, anon, authenticated;
revoke all on function public.expire_unpaid_orders() from public, anon, authenticated;
