alter table public.order_items
  add column seller_shipping_status text not null default 'menunggu_diproses'
  check (seller_shipping_status in ('menunggu_diproses', 'diproses', 'dikirim'));

update public.order_items oi
set seller_shipping_status = 'dikirim'
from public.orders o
where o.id = oi.order_id
  and o.status in ('dikirim', 'selesai');

create or replace function public.seller_list_orders(p_umkm_id uuid)
returns table (
  order_id uuid,
  order_no text,
  customer_name text,
  products jsonb,
  total numeric,
  status public.order_status,
  seller_shipping_status text,
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
    case
      when o.status in ('menunggu_pembayaran', 'dikirim', 'dibatalkan', 'selesai') then o.status
      when bool_and(oi.seller_shipping_status = 'dikirim') then 'dikirim'::public.order_status
      else 'diproses'::public.order_status
    end,
    case
      when o.status in ('menunggu_pembayaran', 'dikirim', 'dibatalkan', 'selesai') then o.status::text
      when bool_and(oi.seller_shipping_status = 'dikirim') then 'dikirim'
      else min(oi.seller_shipping_status)
    end,
    o.created_at
  from public.orders o
  join public.order_items oi on oi.order_id = o.id and oi.umkm_id = p_umkm_id
  left join public.profiles p on p.id = o.user_id
  group by o.id, p.full_name
  order by o.created_at desc;
end;
$$;

create or replace function public.seller_process_order(p_order_id uuid, p_umkm_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.owns_active_umkm(p_umkm_id) then
    raise exception 'Akses ditolak';
  end if;

  perform 1
  from public.orders o
  where o.id = p_order_id
    and o.payment_status = 'dibayar'
    and o.status = 'diproses'
  for update;

  if not found then
    raise exception 'Pesanan tidak tersedia untuk diproses';
  end if;

  if not exists (
    select 1
    from public.order_items oi
    where oi.order_id = p_order_id
      and oi.umkm_id = p_umkm_id
      and oi.seller_shipping_status = 'menunggu_diproses'
  ) then
    raise exception 'Pesanan tidak tersedia untuk diproses';
  end if;

  update public.order_items
  set seller_shipping_status = 'diproses'
  where order_id = p_order_id
    and umkm_id = p_umkm_id
    and seller_shipping_status = 'menunggu_diproses';
end;
$$;

create or replace function public.seller_ship_order(p_order_id uuid, p_umkm_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.owns_active_umkm(p_umkm_id) then
    raise exception 'Akses ditolak';
  end if;

  perform 1
  from public.orders o
  where o.id = p_order_id
    and o.payment_status = 'dibayar'
    and o.status = 'diproses'
  for update;

  if not found then
    raise exception 'Pesanan tidak tersedia untuk dikirim';
  end if;

  if not exists (
    select 1
    from public.order_items oi
    where oi.order_id = p_order_id
      and oi.umkm_id = p_umkm_id
      and oi.seller_shipping_status = 'diproses'
  ) then
    raise exception 'Pesanan tidak tersedia untuk dikirim';
  end if;

  update public.order_items
  set seller_shipping_status = 'dikirim'
  where order_id = p_order_id
    and umkm_id = p_umkm_id
    and seller_shipping_status = 'diproses';
end;
$$;

revoke all on function public.seller_list_orders(uuid) from public, anon;
revoke all on function public.seller_process_order(uuid, uuid) from public, anon;
revoke all on function public.seller_ship_order(uuid, uuid) from public, anon;
grant execute on function public.seller_list_orders(uuid) to authenticated;
grant execute on function public.seller_process_order(uuid, uuid) to authenticated;
grant execute on function public.seller_ship_order(uuid, uuid) to authenticated;
