create or replace function public.seller_dashboard_metrics(p_umkm_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
begin
  if not public.owns_active_umkm(p_umkm_id) then
    raise exception 'Akses ditolak';
  end if;

  return jsonb_build_object(
    'pesanan_baru', (
      select count(distinct oi.order_id)
      from public.order_items oi
      join public.orders o on o.id = oi.order_id
      where oi.umkm_id = p_umkm_id
        and oi.seller_shipping_status = 'menunggu_diproses'
        and o.payment_status = 'dibayar'
        and o.status = 'diproses'
    ),
    'total_pendapatan', (
      select coalesce(sum(oi.unit_price * oi.quantity), 0)
      from public.order_items oi
      join public.orders o on o.id = oi.order_id
      where oi.umkm_id = p_umkm_id
        and o.payment_status = 'dibayar'
        and o.status <> 'dibatalkan'
    ),
    'pendapatan_harian', (
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'tanggal', to_char(days.day, 'YYYY-MM-DD'),
          'omzet', coalesce(totals.omzet, 0)
        ) order by days.day
      ), '[]'::jsonb)
      from generate_series(v_today - 6, v_today, interval '1 day') as days(day)
      left join lateral (
        select coalesce(sum(oi.unit_price * oi.quantity), 0) as omzet
        from public.order_items oi
        join public.orders o on o.id = oi.order_id
        where oi.umkm_id = p_umkm_id
          and o.payment_status = 'dibayar'
          and o.status <> 'dibatalkan'
          and o.paid_at >= (days.day::timestamp at time zone 'Asia/Jakarta')
          and o.paid_at < ((days.day + interval '1 day')::timestamp at time zone 'Asia/Jakarta')
      ) totals on true
    ),
    'penjualan_harian', (
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'tanggal', to_char(days.day, 'YYYY-MM-DD'),
          'jumlah', coalesce(totals.jumlah, 0)
        ) order by days.day
      ), '[]'::jsonb)
      from generate_series(v_today - 6, v_today, interval '1 day') as days(day)
      left join lateral (
        select coalesce(sum(oi.quantity), 0) as jumlah
        from public.order_items oi
        join public.orders o on o.id = oi.order_id
        where oi.umkm_id = p_umkm_id
          and o.payment_status = 'dibayar'
          and o.status <> 'dibatalkan'
          and o.paid_at >= (days.day::timestamp at time zone 'Asia/Jakarta')
          and o.paid_at < ((days.day + interval '1 day')::timestamp at time zone 'Asia/Jakarta')
      ) totals on true
    )
  );
end;
$$;

revoke all on function public.seller_dashboard_metrics(uuid) from public, anon;
grant execute on function public.seller_dashboard_metrics(uuid) to authenticated;
