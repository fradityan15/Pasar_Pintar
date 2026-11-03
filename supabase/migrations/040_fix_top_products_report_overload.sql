drop function if exists public.top_products_report(date, integer, date);
drop function if exists public.top_products_report(date, date, integer);

create function public.top_products_report(
  p_from date,
  p_to date,
  p_limit integer default 5
)
returns table (
  product_name text,
  quantity bigint,
  revenue numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Akses ditolak';
  end if;
  if p_from is null or p_to is null or p_to < p_from then
    raise exception 'Rentang tanggal tidak valid';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception 'Batas hasil harus antara 1 dan 100';
  end if;

  return query
  select
    oi.product_name,
    sum(oi.quantity)::bigint,
    sum(oi.unit_price * oi.quantity)::numeric
  from public.order_items oi
  join public.orders o on o.id = oi.order_id
  where o.payment_status = 'dibayar'
    and o.paid_at is not null
    and o.status <> 'dibatalkan'
    and (o.paid_at at time zone 'Asia/Jakarta')::date between p_from and p_to
  group by oi.product_name
  order by sum(oi.quantity) desc, sum(oi.unit_price * oi.quantity) desc, oi.product_name
  limit p_limit;
end;
$$;

revoke all on function public.top_products_report(date, date, integer) from public, anon;
grant execute on function public.top_products_report(date, date, integer) to authenticated;
