create table if not exists public.payment_methods (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  category text not null check (category in ('qris', 'va', 'bank_transfer', 'cod')),
  account_number text,
  account_name text,
  qr_image_url text,
  is_active boolean not null default true,
  constraint payment_methods_account_details_check
    check (
      category not in ('va', 'bank_transfer')
      or (
        nullif(trim(account_number), '') is not null
        and nullif(trim(account_name), '') is not null
      )
    ),
  constraint payment_methods_qr_image_check
    check (category <> 'qris' or nullif(trim(qr_image_url), '') is not null)
);

alter table public.payment_methods enable row level security;

drop policy if exists "Active payment methods are publicly readable" on public.payment_methods;
create policy "Active payment methods are publicly readable"
  on public.payment_methods
  for select
  to anon, authenticated
  using (is_active);

grant select on public.payment_methods to anon, authenticated;

alter table public.orders
  add column if not exists payment_method_id uuid;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'orders_payment_method_id_fkey'
      and conrelid = 'public.orders'::regclass
  ) then
    alter table public.orders
      add constraint orders_payment_method_id_fkey
      foreign key (payment_method_id)
      references public.payment_methods(id)
      on delete restrict;
  end if;
end
$$;

alter table public.orders
  add column if not exists shipping_method text not null default 'regular';

alter table public.orders
  drop constraint if exists orders_shipping_method_check;

alter table public.orders
  add constraint orders_shipping_method_check
  check (shipping_method in ('regular', 'economy'));

alter table public.orders
  drop constraint if exists orders_payment_method_check;

alter table public.orders
  add constraint orders_payment_method_check
  check (
    payment_method in (
      'qris',
      'virtual_account',
      'bank_transfer',
      'cod',
      'va-bca',
      'va-mandiri',
      'va-bri',
      'va-bni'
    )
  );

alter table public.orders
  alter column payment_status drop default;

alter table public.orders
  alter column payment_status type text using payment_status::text;

alter table public.orders
  alter column payment_status set default 'pending';

alter table public.orders
  drop constraint if exists orders_payment_status_check;

alter table public.orders
  add constraint orders_payment_status_check
  check (payment_status in ('pending', 'belum_dibayar', 'dibayar', 'kedaluwarsa'));

drop function if exists public.create_order(uuid, text);
drop function if exists public.create_order(uuid, text, uuid[]);
drop function if exists public.create_order(uuid, text, uuid[], text);

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
  v_uid           uuid := auth.uid();
  v_addr          public.addresses%rowtype;
  v_payment       public.payment_methods%rowtype;
  v_order_id      uuid;
  v_product_ids   uuid[];
  v_cart_count    bigint;
  v_item_count    bigint := 0;
  v_subtotal      numeric := 0;
  v_shipping      numeric;
  v_payment_type  text;
  r               record;
begin
  if v_uid is null then
    raise exception 'Silakan login terlebih dahulu';
  end if;

  select *
  into v_payment
  from public.payment_methods
  where id = p_payment_method_id
    and is_active
  for share;

  if not found then
    raise exception 'Metode pembayaran tidak ditemukan atau tidak aktif';
  end if;

  v_payment_type := case
    when v_payment.category = 'qris' then 'qris'
    when v_payment.category in ('va', 'bank_transfer') then 'virtual_account'
    else 'cod'
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
    and user_id = v_uid
  for share;

  if not found then
    raise exception 'Alamat tidak ditemukan';
  end if;

  if p_product_ids is null then
    select array_agg(locked_cart.product_id order by locked_cart.product_id)
    into v_product_ids
    from (
      select product_id
      from public.cart_items
      where user_id = v_uid
      order by product_id
      for update
    ) as locked_cart;
  else
    v_product_ids := p_product_ids;
  end if;

  if coalesce(cardinality(v_product_ids), 0) = 0 then
    raise exception 'Keranjang kosong';
  end if;

  select count(distinct selected.product_id)
  into v_cart_count
  from unnest(v_product_ids) as selected(product_id);

  if v_cart_count <> cardinality(v_product_ids) then
    raise exception 'Daftar produk tidak valid';
  end if;

  for r in
    select p.id, p.name, p.price, p.stock, p.is_active, c.quantity
    from public.cart_items as c
    join public.products as p on p.id = c.product_id
    where c.user_id = v_uid
      and c.product_id = any(v_product_ids)
    order by p.id
    for update of c, p
  loop
    v_item_count := v_item_count + 1;

    if not r.is_active then
      raise exception 'Produk "%" tidak tersedia', r.name;
    end if;
    if r.stock < r.quantity then
      raise exception 'Stok "%" tidak cukup (tersisa %)', r.name, r.stock;
    end if;

    v_subtotal := v_subtotal + r.price * r.quantity;
  end loop;

  if v_item_count <> cardinality(v_product_ids) then
    raise exception 'Sebagian produk pilihan tidak lagi tersedia di keranjang';
  end if;

  insert into public.orders (
    user_id,
    payment_method,
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
    v_payment_type,
    v_payment.id,
    p_shipping_method,
    v_subtotal,
    v_shipping,
    v_subtotal + v_shipping,
    to_jsonb(v_addr) - 'id' - 'user_id' - 'created_at' - 'is_default',
    case when v_payment.category = 'cod' then null else now() + interval '24 hours' end
  )
  returning id into v_order_id;

  for r in
    select p.id, p.name, p.price, p.umkm_id, c.quantity
    from public.cart_items as c
    join public.products as p on p.id = c.product_id
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

revoke execute on function public.create_order(uuid, uuid, uuid[], text) from public, anon;
grant execute on function public.create_order(uuid, uuid, uuid[], text) to authenticated;
