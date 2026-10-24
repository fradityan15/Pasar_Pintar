alter table public.orders
  add column shipping_method text not null default 'regular'
  check (shipping_method in ('regular', 'economy'));

drop function public.create_order(uuid, text, uuid[]);

create function public.create_order(
  p_address_id uuid,
  p_payment_method text,
  p_product_ids uuid[],
  p_shipping_method text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid         uuid := auth.uid();
  v_addr        public.addresses%rowtype;
  v_order_id    uuid;
  v_product_ids uuid[];
  v_cart_count  bigint;
  v_subtotal    numeric := 0;
  v_shipping    numeric;
  r             record;
begin
  if v_uid is null then raise exception 'Silakan login terlebih dahulu'; end if;
  if p_payment_method not in ('qris', 'virtual_account') then
    raise exception 'Metode pembayaran tidak valid';
  end if;

  v_shipping := case p_shipping_method
    when 'regular' then 15000
    when 'economy' then 10000
    else null
  end;
  if v_shipping is null then
    raise exception 'Metode pengiriman tidak valid';
  end if;

  select * into v_addr
  from public.addresses
  where id = p_address_id and user_id = v_uid;
  if not found then raise exception 'Alamat tidak ditemukan'; end if;

  if p_product_ids is null then
    select array_agg(product_id) into v_product_ids
    from public.cart_items
    where user_id = v_uid;
  else
    v_product_ids := p_product_ids;
  end if;

  if coalesce(cardinality(v_product_ids), 0) = 0 then
    raise exception 'Keranjang kosong';
  end if;

  select count(distinct product_id) into v_cart_count
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
    if not r.is_active then raise exception 'Produk "%" tidak tersedia', r.name; end if;
    if r.stock < r.quantity then
      raise exception 'Stok "%" tidak cukup (tersisa %)', r.name, r.stock;
    end if;
    v_subtotal := v_subtotal + r.price * r.quantity;
  end loop;

  insert into public.orders (
    user_id, payment_method, shipping_method, subtotal, shipping_cost, total, shipping_address, payment_expires_at
  )
  values (
    v_uid, p_payment_method, p_shipping_method, v_subtotal, v_shipping, v_subtotal + v_shipping,
    to_jsonb(v_addr) - 'id' - 'user_id' - 'created_at' - 'is_default',
    now() + interval '24 hours'
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
    insert into public.order_items (order_id, product_id, umkm_id, product_name, unit_price, quantity)
    values (v_order_id, r.id, r.umkm_id, r.name, r.price, r.quantity);

    update public.products set stock = stock - r.quantity where id = r.id;
    insert into public.stock_movements (product_id, change, reason, order_id, created_by)
    values (r.id, -r.quantity, 'pesanan', v_order_id, v_uid);
  end loop;

  insert into public.order_status_logs (order_id, status, changed_by, note)
  values (v_order_id, 'menunggu_pembayaran', v_uid, 'Pesanan dibuat');

  delete from public.cart_items
  where user_id = v_uid and product_id = any(v_product_ids);

  return v_order_id;
end;
$$;

revoke execute on function public.create_order(uuid, text, uuid[], text) from public, anon;
grant execute on function public.create_order(uuid, text, uuid[], text) to authenticated;
