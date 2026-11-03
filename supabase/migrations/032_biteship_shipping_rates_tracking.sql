-- Biteship rates and tracking. Quotes are short-lived and server-created.

alter table public.addresses
  add column if not exists biteship_area_id text;
alter table public.umkm
  add column if not exists biteship_origin_area_id text;

alter table public.orders
  add column if not exists courier text,
  add column if not exists courier_service text,
  add column if not exists tracking_number text,
  add column if not exists shipping_quote_id uuid;

alter table public.order_items
  add column if not exists courier text,
  add column if not exists courier_service text,
  add column if not exists shipping_cost numeric(12, 0) not null default 0,
  add column if not exists tracking_number text;

alter table public.orders
  drop constraint if exists orders_shipping_method_check,
  add constraint orders_shipping_method_check
    check (shipping_method in ('regular', 'economy', 'courier_api'));

create table public.shipping_quotes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  address_id uuid not null references public.addresses(id) on delete cascade,
  item_snapshot jsonb not null,
  options jsonb not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at timestamptz
);
create index shipping_quotes_user_expiry_idx on public.shipping_quotes (user_id, expires_at desc);
alter table public.shipping_quotes enable row level security;
revoke all on public.shipping_quotes from public, anon, authenticated;
grant select on public.shipping_quotes to authenticated;
create policy shipping_quotes_owner_read on public.shipping_quotes for select to authenticated
  using (user_id = (select auth.uid()));

create table public.shipping_tracking_cache (
  order_id uuid not null references public.orders(id) on delete cascade,
  courier text not null,
  tracking_number text not null,
  response jsonb not null,
  fetched_at timestamptz not null default now(),
  expires_at timestamptz not null,
  primary key (order_id, courier, tracking_number)
);
alter table public.shipping_tracking_cache enable row level security;
revoke all on public.shipping_tracking_cache from public, anon, authenticated;

create table public.shipment_events (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.orders(id) on delete cascade,
  courier text not null,
  tracking_number text not null,
  event_key text not null,
  status text not null,
  description text,
  occurred_at timestamptz not null,
  created_at timestamptz not null default now(),
  constraint shipment_events_external_key_unique unique (order_id, event_key)
);
create index shipment_events_order_timeline_idx
  on public.shipment_events (order_id, occurred_at desc);
alter table public.shipment_events enable row level security;
revoke all on public.shipment_events from public, anon, authenticated;
grant select on public.shipment_events to authenticated;
create policy shipment_events_order_read on public.shipment_events for select to authenticated
  using (
    exists (
      select 1 from public.orders o
      where o.id = shipment_events.order_id
        and (o.user_id = (select auth.uid()) or public.is_admin() or public.seller_owns_order(o.id))
    )
  );
grant all on public.shipping_quotes, public.shipping_tracking_cache, public.shipment_events to service_role;

drop function if exists public.create_order(uuid, uuid, uuid[], text);
create function public.create_order(
  p_address_id uuid,
  p_payment_method_id uuid,
  p_product_ids uuid[],
  p_shipping_quote_id uuid,
  p_shipping_option_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_addr public.addresses%rowtype;
  v_quote public.shipping_quotes%rowtype;
  v_order_id uuid;
  v_product_ids uuid[];
  v_payment_category text;
  v_initial_status public.order_status;
  v_cart_count bigint;
  v_subtotal numeric := 0;
  v_shipping numeric(12, 0);
  v_snapshot jsonb;
  v_item_snapshot jsonb;
  v_option jsonb;
  v_shipments jsonb;
  v_courier text;
  v_service text;
  v_item_shipping numeric(12, 0);
  v_seller_shipping numeric(12, 0);
  v_allocated_seller_shipping numeric(12, 0) := 0;
  v_current_umkm_id uuid;
  r record;
begin
  if v_uid is null then raise exception 'Silakan login terlebih dahulu'; end if;

  select * into v_addr from public.addresses
  where id = p_address_id and user_id = v_uid;
  if not found or nullif(trim(v_addr.biteship_area_id), '') is null then
    raise exception 'Alamat belum memiliki kode area pengiriman';
  end if;

  select * into v_quote from public.shipping_quotes
  where id = p_shipping_quote_id and user_id = v_uid
  for update;
  if not found or v_quote.address_id <> p_address_id
    or v_quote.expires_at <= now() or v_quote.used_at is not null then
    raise exception 'Tarif pengiriman kedaluwarsa atau tidak valid; hitung ulang tarif';
  end if;
  if p_product_ids is null or cardinality(p_product_ids) = 0 then
    raise exception 'Pilih produk untuk checkout';
  end if;
  v_product_ids := p_product_ids;
  select count(distinct c.product_id), jsonb_agg(
      jsonb_build_object(
        'product_id', p.id,
        'quantity', c.quantity,
        'price', p.price,
        'weight_gram', p.weight_gram,
        'umkm_id', u.id,
        'origin_area_id', u.biteship_origin_area_id
      ) order by p.id
    )
  into v_cart_count, v_item_snapshot
  from public.cart_items c
  join public.products p on p.id = c.product_id
  join public.umkm u on u.id = p.umkm_id
  where c.user_id = v_uid and c.product_id = any(v_product_ids);
  v_snapshot := jsonb_build_object(
    'destination_area_id', v_addr.biteship_area_id,
    'items', coalesce(v_item_snapshot, '[]'::jsonb)
  );
  if v_cart_count <> cardinality(v_product_ids) or v_snapshot <> v_quote.item_snapshot then
    raise exception 'Isi keranjang berubah; minta tarif pengiriman yang baru';
  end if;

  select opt.value into v_option
  from jsonb_array_elements(v_quote.options) as opt(value)
  where opt.value->>'id' = p_shipping_option_id::text
  limit 1;
  if v_option is null then raise exception 'Pilihan tarif tidak ditemukan'; end if;
  v_shipping := (v_option->>'shipping_cost')::numeric(12, 0);
  v_shipments := v_option->'shipments';
  if v_shipping < 0 or jsonb_typeof(v_shipments) <> 'array' then
    raise exception 'Data tarif pengiriman tidak valid';
  end if;
  if v_shipping <> (
    select coalesce(sum((ship.value->>'shipping_cost')::numeric), 0)
    from jsonb_array_elements(v_shipments) as ship(value)
  ) or jsonb_array_length(v_shipments) <> (
    select count(distinct p.umkm_id)
    from public.cart_items c join public.products p on p.id = c.product_id
    where c.user_id = v_uid and c.product_id = any(v_product_ids)
  ) then
    raise exception 'Rincian tarif pengiriman tidak konsisten';
  end if;

  select pm.category into v_payment_category
  from public.payment_methods pm
  where pm.id = p_payment_method_id and pm.is_active
  for share;
  if not found then raise exception 'Metode pembayaran tidak ditemukan atau tidak aktif'; end if;
  v_initial_status := case when v_payment_category = 'cod'
    then 'menunggu_diproses'::public.order_status
    else 'menunggu_pembayaran'::public.order_status end;

  for r in
    select p.id, p.name, p.price, p.stock, p.is_active, p.umkm_id, c.quantity,
      u.status as umkm_status, u.is_active as umkm_is_active, u.is_verified as umkm_is_verified
    from public.cart_items c
    join public.products p on p.id = c.product_id
    join public.umkm u on u.id = p.umkm_id
    where c.user_id = v_uid and c.product_id = any(v_product_ids)
    order by p.id for update of p
  loop
    if not r.is_active then raise exception 'Produk "%" tidak tersedia', r.name; end if;
    if r.umkm_status <> 'active' or not r.umkm_is_active or not r.umkm_is_verified then
      raise exception 'Toko produk "%" belum tersedia untuk pesanan', r.name;
    end if;
    if r.stock < r.quantity then raise exception 'Stok "%" tidak cukup (tersisa %)', r.name, r.stock; end if;
    if not exists (select 1 from jsonb_array_elements(v_shipments) as ship(value)
      where ship.value->>'umkm_id' = r.umkm_id::text) then
      raise exception 'Opsi pengiriman untuk salah satu toko tidak tersedia';
    end if;
    v_subtotal := v_subtotal + r.price * r.quantity;
  end loop;

  select
    case when count(distinct ship.value->>'courier_code') = 1
      then max(ship.value->>'courier_code') else 'multiple' end,
    case when count(distinct ship.value->>'service_code') = 1
      then max(ship.value->>'service_code') else 'multiple' end
  into v_courier, v_service
  from jsonb_array_elements(v_shipments) as ship(value);

  insert into public.orders (
    user_id, payment_method_id, shipping_method, subtotal, shipping_cost, total,
    shipping_address, payment_expires_at, status, courier, courier_service, shipping_quote_id
  ) values (
    v_uid, p_payment_method_id, 'courier_api', v_subtotal, v_shipping,
    v_subtotal + v_shipping,
    to_jsonb(v_addr) - 'id' - 'user_id' - 'created_at' - 'is_default',
    case when v_payment_category = 'cod' then null else now() + interval '24 hours' end,
    v_initial_status, v_courier, v_service, v_quote.id
  ) returning id into v_order_id;

  for r in
    select p.id, p.name, p.price, p.umkm_id, c.quantity,
      sum(p.price * c.quantity) over (partition by p.umkm_id) as umkm_subtotal,
      last_value(p.id) over (
        partition by p.umkm_id order by p.id
        rows between unbounded preceding and unbounded following
      ) as last_product_id
    from public.cart_items c join public.products p on p.id = c.product_id
    where c.user_id = v_uid and c.product_id = any(v_product_ids)
    order by p.umkm_id, p.id
  loop
    if v_current_umkm_id is distinct from r.umkm_id then
      v_current_umkm_id := r.umkm_id;
      v_allocated_seller_shipping := 0;
    end if;

    select ship.value->>'courier_code', ship.value->>'service_name',
      (ship.value->>'shipping_cost')::numeric(12, 0)
    into v_courier, v_service, v_seller_shipping
    from jsonb_array_elements(v_shipments) as ship(value)
    where ship.value->>'umkm_id' = r.umkm_id::text
    limit 1;
    if r.id = r.last_product_id then
      v_item_shipping := v_seller_shipping - v_allocated_seller_shipping;
    elsif r.umkm_subtotal <= 0 then
      v_item_shipping := 0;
    else
      v_item_shipping := round(v_seller_shipping * r.price * r.quantity / r.umkm_subtotal, 0);
      v_allocated_seller_shipping := v_allocated_seller_shipping + v_item_shipping;
    end if;

    insert into public.order_items (
      order_id, product_id, umkm_id, product_name, unit_price, quantity, courier, courier_service, shipping_cost
    ) values (
      v_order_id, r.id, r.umkm_id, r.name, r.price, r.quantity, v_courier, v_service, v_item_shipping
    );
    update public.products set stock = stock - r.quantity where id = r.id;
    insert into public.stock_movements (product_id, change, reason, order_id, created_by)
    values (r.id, -r.quantity, 'pesanan', v_order_id, v_uid);
  end loop;

  insert into public.order_status_logs (order_id, status, changed_by, note)
  values (v_order_id, v_initial_status, v_uid,
    case when v_payment_category = 'cod' then 'Pesanan COD dibuat' else 'Pesanan dibuat' end);
  delete from public.cart_items where user_id = v_uid and product_id = any(v_product_ids);
  update public.shipping_quotes set used_at = now() where id = v_quote.id;
  return v_order_id;
end;
$$;
revoke all on function public.create_order(uuid, uuid, uuid[], uuid, uuid) from public, anon;
grant execute on function public.create_order(uuid, uuid, uuid[], uuid, uuid) to authenticated;

drop function if exists public.seller_ship_order(uuid, uuid);
create function public.seller_ship_order(
  p_order_id uuid,
  p_umkm_id uuid,
  p_courier text,
  p_tracking_number text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_payment_category text;
  v_all_shipped boolean;
  v_service text;
begin
  if not public.owns_active_umkm(p_umkm_id) then raise exception 'Akses ditolak'; end if;
  if p_courier is null or p_courier !~ '^[a-z0-9_-]{2,30}$'
    or p_tracking_number is null or p_tracking_number !~ '^[A-Za-z0-9-]{6,40}$' then
    raise exception 'Kurir atau nomor resi tidak valid';
  end if;
  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.status <> 'diproses' then raise exception 'Pesanan tidak tersedia untuk dikirim'; end if;
  select coalesce(pm.category, case when v_order.payment_method = 'cod' then 'cod' end)
  into v_payment_category
  from (select 1) singleton left join public.payment_methods pm on pm.id = v_order.payment_method_id;
  if v_order.payment_status::text <> 'dibayar' and v_payment_category <> 'cod' then
    raise exception 'Pembayaran pesanan belum dikonfirmasi';
  end if;
  select max(oi.courier_service) into v_service
  from public.order_items oi
  where oi.order_id = p_order_id and oi.umkm_id = p_umkm_id;
  if not exists (
    select 1 from public.order_items oi
    where oi.order_id = p_order_id and oi.umkm_id = p_umkm_id
      and oi.seller_shipping_status = 'diproses'
      and oi.courier = p_courier
  ) then raise exception 'Kurir tidak sesuai tarif yang dipilih atau pesanan tidak siap dikirim'; end if;

  update public.order_items
  set seller_shipping_status = 'dikirim', tracking_number = upper(p_tracking_number)
  where order_id = p_order_id and umkm_id = p_umkm_id
    and seller_shipping_status = 'diproses' and courier = p_courier;
  if not found then raise exception 'Pesanan tidak tersedia untuk dikirim'; end if;

  select not exists (select 1 from public.order_items
    where order_id = p_order_id and seller_shipping_status <> 'dikirim')
  into v_all_shipped;
  if v_all_shipped then
    update public.orders set status = 'dikirim',
      tracking_number = case when (select count(distinct tracking_number)
        from public.order_items where order_id = p_order_id) = 1 then upper(p_tracking_number) else null end
    where id = p_order_id and status = 'diproses';
    insert into public.order_status_logs (order_id, status, changed_by, note)
    values (p_order_id, 'dikirim', auth.uid(), 'Seluruh mitra telah mengirim barang');
  else
    insert into public.order_status_logs (order_id, status, changed_by, note)
    values (p_order_id, 'diproses', auth.uid(), 'Toko mengirim barang dengan kurir ' || p_courier);
  end if;
  insert into public.shipment_events (order_id, courier, tracking_number, event_key, status, description, occurred_at)
  select p_order_id, p_courier, upper(p_tracking_number),
    'seller-shipped-' || p_umkm_id::text, 'dikirim', 'Paket telah diserahkan kepada kurir',
    now()
  on conflict (order_id, event_key) do nothing;
end;
$$;
revoke all on function public.seller_ship_order(uuid, uuid, text, text) from public, anon;
grant execute on function public.seller_ship_order(uuid, uuid, text, text) to authenticated;

drop function public.seller_list_orders(uuid);
create function public.seller_list_orders(p_umkm_id uuid)
returns table (
  order_id uuid, order_no text, customer_name text, products jsonb, total numeric,
  status public.order_status, seller_shipping_status text, payment_status text,
  payment_category text, created_at timestamptz, courier text, courier_service text
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.owns_active_umkm(p_umkm_id) then raise exception 'Akses ditolak'; end if;
  return query
  select o.id, o.order_no, coalesce(p.full_name, 'Pembeli'),
    jsonb_agg(jsonb_build_object('product_name', oi.product_name, 'quantity', oi.quantity,
      'unit_price', oi.unit_price, 'courier', oi.courier, 'courier_service', oi.courier_service,
      'tracking_number', oi.tracking_number) order by oi.id),
    sum(oi.unit_price * oi.quantity), o.status,
    case when bool_and(oi.seller_shipping_status = 'dikirim') then 'dikirim'
      when bool_or(oi.seller_shipping_status = 'diproses') then 'diproses'
      else 'menunggu_diproses' end,
    o.payment_status, coalesce(pm.category, case when o.payment_method = 'cod' then 'cod' end),
    o.created_at, max(oi.courier), max(oi.courier_service)
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

create or replace function public.get_my_store_settings(p_umkm_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public
as $$
declare v public.umkm%rowtype;
begin
  if not public.owns_active_umkm(p_umkm_id) then raise exception 'Akses ditolak'; end if;
  select * into v from public.umkm where id = p_umkm_id;
  return jsonb_build_object(
    'id', v.id, 'name', v.name, 'tagline', v.tagline, 'description', v.description,
    'address', v.address, 'region_id', v.region_id, 'logo_url', v.logo_url,
    'banner_url', v.banner_url, 'shipping_providers', v.shipping_providers,
    'bank_name', v.bank_name, 'bank_account_number', v.bank_account_number,
    'bank_account_holder', v.bank_account_holder, 'opening_hours', v.opening_hours,
    'biteship_origin_area_id', v.biteship_origin_area_id
  );
end;
$$;

create or replace function public.save_my_store_settings(p_umkm_id uuid, p_settings jsonb)
returns void language plpgsql security definer set search_path = public
as $$
declare
  v_providers text[];
  v_allowed_providers constant text[] := array['JNE', 'POS Indonesia', 'TIKI', 'SiCepat', 'J&T Express', 'AnterAja'];
  v_area_id text := nullif(trim(p_settings->>'biteship_origin_area_id'), '');
begin
  if not public.owns_active_umkm(p_umkm_id) then raise exception 'Akses ditolak'; end if;
  if nullif(trim(p_settings->>'name'), '') is null then raise exception 'Nama toko wajib diisi'; end if;
  if v_area_id is null or length(v_area_id) > 80 then
    raise exception 'Kode area asal Biteship wajib diisi';
  end if;
  select coalesce(array_agg(p.provider), '{}') into v_providers
  from jsonb_array_elements_text(coalesce(p_settings->'shipping_providers', '[]'::jsonb)) as p(provider);
  if exists (select 1 from unnest(v_providers) p(provider) where p.provider <> all(v_allowed_providers)) then
    raise exception 'Jasa kurir tidak valid';
  end if;
  update public.umkm set
    name = trim(p_settings->>'name'), tagline = nullif(trim(p_settings->>'tagline'), ''),
    description = nullif(trim(p_settings->>'description'), ''),
    address = nullif(trim(p_settings->>'address'), ''),
    region_id = nullif(p_settings->>'region_id', '')::uuid,
    logo_url = nullif(p_settings->>'logo_url', ''), banner_url = nullif(p_settings->>'banner_url', ''),
    shipping_providers = v_providers,
    bank_name = nullif(trim(p_settings->>'bank_name'), ''),
    bank_account_number = nullif(trim(p_settings->>'bank_account_number'), ''),
    bank_account_holder = nullif(trim(p_settings->>'bank_account_holder'), ''),
    opening_hours = coalesce(p_settings->'opening_hours', '{}'::jsonb),
    biteship_origin_area_id = v_area_id
  where id = p_umkm_id;
end;
$$;
revoke all on function public.get_my_store_settings(uuid), public.save_my_store_settings(uuid, jsonb) from public, anon;
grant execute on function public.get_my_store_settings(uuid), public.save_my_store_settings(uuid, jsonb) to authenticated;
