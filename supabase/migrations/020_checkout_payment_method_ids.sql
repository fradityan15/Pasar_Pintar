alter table public.orders
  drop constraint if exists orders_payment_method_check,
  add column if not exists payment_method_id uuid;

alter table public.orders
  alter column payment_method drop not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.orders'::regclass
      and conname = 'orders_payment_method_id_fkey'
  ) then
    alter table public.orders
      add constraint orders_payment_method_id_fkey
      foreign key (payment_method_id)
      references public.payment_methods(id)
      on delete restrict;
  end if;
end;
$$;

drop function if exists public.create_order(uuid, text, uuid[], text);

create function public.create_order(
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
    payment_expires_at
  )
  values (
    v_uid,
    p_payment_method_id,
    p_shipping_method,
    v_subtotal,
    v_shipping,
    v_subtotal + v_shipping,
    to_jsonb(v_addr) - 'id' - 'user_id' - 'created_at' - 'is_default',
    case when v_payment_category = 'cod' then null else now() + interval '24 hours' end
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
  values (v_order_id, 'menunggu_pembayaran', v_uid, 'Pesanan dibuat');

  delete from public.cart_items
  where user_id = v_uid
    and product_id = any(v_product_ids);

  return v_order_id;
end;
$$;

revoke all on function public.create_order(uuid, uuid, uuid[], text) from public, anon;
grant execute on function public.create_order(uuid, uuid, uuid[], text) to authenticated;

create or replace function public.simulate_payment_confirmation(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_payment_category text;
  v_note text;
begin
  if auth.uid() is null then
    raise exception 'Silakan login terlebih dahulu';
  end if;

  select *
  into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found or v_order.user_id <> auth.uid() then
    raise exception 'Pesanan tidak ditemukan';
  end if;

  if v_order.status <> 'menunggu_pembayaran'
    or v_order.payment_status not in ('pending', 'belum_dibayar') then
    raise exception 'Pesanan ini tidak sedang menunggu pembayaran';
  end if;

  if v_order.payment_expires_at is not null and v_order.payment_expires_at <= now() then
    raise exception 'Batas waktu pembayaran telah berakhir';
  end if;

  select pm.category
  into v_payment_category
  from public.payment_methods pm
  where pm.id = v_order.payment_method_id;

  v_note := case
    when coalesce(v_payment_category, case when v_order.payment_method = 'cod' then 'cod' end) = 'cod'
      then 'Simulasi konfirmasi pembayaran COD'
    else 'Simulasi pembayaran berhasil'
  end;

  update public.orders
  set payment_status = 'dibayar',
      status = 'diproses'
  where id = p_order_id;

  insert into public.order_status_logs (order_id, status, changed_by, note)
  values (p_order_id, 'diproses', auth.uid(), v_note);
end;
$$;

revoke all on function public.simulate_payment_confirmation(uuid) from public, anon;
grant execute on function public.simulate_payment_confirmation(uuid) to authenticated;
