drop function if exists public.simulate_payment(uuid);

create or replace function public.admin_dashboard_charts()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
  v_month_start date;
  v_week_start date;
begin
  if not public.is_admin() then
    raise exception 'Akses ditolak';
  end if;

  v_month_start := date_trunc('month', v_today::timestamp)::date - interval '5 months';
  v_week_start := v_today - (extract(isodow from v_today)::integer - 1);

  return jsonb_build_object(
    'umkm', (
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'bulan', to_char(months.month_start, 'YYYY-MM'),
          'aktif', coalesce(totals.aktif, 0),
          'pending', coalesce(totals.pending, 0)
        ) order by months.month_start
      ), '[]'::jsonb)
      from generate_series(v_month_start, date_trunc('month', v_today::timestamp)::date, interval '1 month') as months(month_start)
      left join lateral (
        select
          count(*) filter (where u.status = 'active') as aktif,
          count(*) filter (where u.status = 'pending') as pending
        from public.umkm u
        where u.created_at >= (months.month_start::timestamp at time zone 'Asia/Jakarta')
          and u.created_at < ((months.month_start + interval '1 month')::timestamp at time zone 'Asia/Jakarta')
      ) totals on true
    ),
    'gmv', (
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'minggu_mulai', to_char(weeks.week_start, 'YYYY-MM-DD'),
          'total', coalesce(totals.total, 0)
        ) order by weeks.week_start
      ), '[]'::jsonb)
      from generate_series(v_week_start - interval '4 weeks', v_week_start, interval '1 week') as weeks(week_start)
      left join lateral (
        select coalesce(sum(o.subtotal), 0) as total
        from public.orders o
        where o.payment_status = 'dibayar'
          and o.status <> 'dibatalkan'
          and o.created_at >= (weeks.week_start::timestamp at time zone 'Asia/Jakarta')
          and o.created_at < ((weeks.week_start + interval '1 week')::timestamp at time zone 'Asia/Jakarta')
      ) totals on true
    ),
    'pesanan_harian', (
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'tanggal', to_char(days.day, 'YYYY-MM-DD'),
          'jumlah', coalesce(totals.jumlah, 0)
        ) order by days.day
      ), '[]'::jsonb)
      from generate_series(v_today - 6, v_today, interval '1 day') as days(day)
      left join lateral (
        select count(*) as jumlah
        from public.orders o
        where o.created_at >= (days.day::timestamp at time zone 'Asia/Jakarta')
          and o.created_at < ((days.day + interval '1 day')::timestamp at time zone 'Asia/Jakarta')
      ) totals on true
    )
  );
end;
$$;

create or replace function public.seller_dashboard_metrics(p_umkm_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
  v_metrics jsonb;
begin
  if not public.owns_active_umkm(p_umkm_id) then
    raise exception 'Akses ditolak';
  end if;

  select jsonb_build_object(
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
    )
  ) into v_metrics;

  return v_metrics;
end;
$$;

revoke all on function public.admin_dashboard_charts() from public, anon;
revoke all on function public.seller_dashboard_metrics(uuid) from public, anon;
grant execute on function public.admin_dashboard_charts() to authenticated;
grant execute on function public.seller_dashboard_metrics(uuid) to authenticated;
