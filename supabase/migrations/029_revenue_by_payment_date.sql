-- Revenue reporting uses the local calendar date on which payment was recorded.
-- The canonical paid status is 'dibayar'; 'paid' is not allowed by the current constraint.

create or replace function public.dashboard_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
begin
  if not public.is_admin() then
    raise exception 'Akses ditolak';
  end if;

  return jsonb_build_object(
    'total_produk', (select count(*) from public.products),
    'pesanan_selesai', (select count(*) from public.orders where status = 'selesai'),
    'pesanan_dibatalkan', (select count(*) from public.orders where status = 'dibatalkan'),
    'umkm_aktif', (select count(*) from public.umkm where is_active),
    'menunggu_pembayaran', (select count(*) from public.orders where status = 'menunggu_pembayaran'),
    'stok_menipis', (select count(*) from public.products where is_active and stock <= 10),
    'umkm_belum_verifikasi', (select count(*) from public.umkm where not is_verified),
    'omzet_7_hari', coalesce((
      select sum(o.total)
      from public.orders o
      where o.payment_status = 'dibayar'
        and o.status <> 'dibatalkan'
        and o.paid_at is not null
        and (o.paid_at at time zone 'Asia/Jakarta')::date between v_today - 6 and v_today
    ), 0)
  );
end;
$$;

create or replace function public.sales_report(p_from date, p_to date)
returns table (tanggal date, jumlah_pesanan bigint, omzet numeric)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Akses ditolak';
  end if;

  return query
    select d.day::date, count(o.id), coalesce(sum(o.total), 0)
    from generate_series(p_from, p_to, interval '1 day') as d(day)
    left join public.orders o
      on (o.paid_at at time zone 'Asia/Jakarta')::date = d.day::date
     and o.payment_status = 'dibayar'
     and o.paid_at is not null
     and o.status <> 'dibatalkan'
    group by d.day
    order by d.day;
end;
$$;

create or replace function public.top_products_report(
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
          and o.paid_at is not null
          and o.status <> 'dibatalkan'
          and (o.paid_at at time zone 'Asia/Jakarta')::date >= weeks.week_start::date
          and (o.paid_at at time zone 'Asia/Jakarta')::date < (weeks.week_start + interval '1 week')::date
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
        -- This is an order-intake metric, so it intentionally uses created_at, not paid_at.
        select count(*) as jumlah
        from public.orders o
        where (o.created_at at time zone 'Asia/Jakarta')::date = days.day::date
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
        and o.paid_at is not null
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
          and o.paid_at is not null
          and o.status <> 'dibatalkan'
          and (o.paid_at at time zone 'Asia/Jakarta')::date = days.day::date
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
          and o.paid_at is not null
          and o.status <> 'dibatalkan'
          and (o.paid_at at time zone 'Asia/Jakarta')::date = days.day::date
      ) totals on true
    )
  );
end;
$$;

create or replace function public.admin_global_analytics()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
  v_start date;
begin
  if not public.is_admin() then
    raise exception 'Akses ditolak';
  end if;

  v_start := v_today - 29;

  return jsonb_build_object(
    'total_transaksi_sukses', (
      select count(*)
      from public.orders o
      where o.payment_status = 'dibayar'
        and o.paid_at is not null
        and o.status <> 'dibatalkan'
    ),
    'total_pendapatan_platform', (
      select coalesce(sum(o.subtotal), 0)
      from public.orders o
      where o.payment_status = 'dibayar'
        and o.paid_at is not null
        and o.status <> 'dibatalkan'
    ),
    'jumlah_umkm_aktif', (
      select count(*)
      from public.umkm u
      where u.status = 'active'
        and u.is_active
    ),
    'total_pengguna', (
      select count(*)
      from public.profiles
    ),
    'tren_transaksi_30_hari', (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'tanggal', to_char(days.day, 'YYYY-MM-DD'),
            'jumlah', coalesce(totals.jumlah, 0)
          )
          order by days.day
        ),
        '[]'::jsonb
      )
      from generate_series(v_start, v_today, interval '1 day') as days(day)
      left join lateral (
        select count(*) as jumlah
        from public.orders o
        where o.payment_status = 'dibayar'
          and o.paid_at is not null
          and o.status <> 'dibatalkan'
          and (o.paid_at at time zone 'Asia/Jakarta')::date = days.day::date
      ) totals on true
    ),
    'top_umkm', (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'umkm_id', leaderboard.umkm_id,
            'nama', leaderboard.nama,
            'jumlah_transaksi', leaderboard.jumlah_transaksi,
            'total_penjualan', leaderboard.total_penjualan
          )
          order by leaderboard.total_penjualan desc, leaderboard.nama
        ),
        '[]'::jsonb
      )
      from (
        select
          u.id as umkm_id,
          u.name as nama,
          count(distinct o.id) as jumlah_transaksi,
          sum(oi.unit_price * oi.quantity) as total_penjualan
        from public.umkm u
        join public.order_items oi on oi.umkm_id = u.id
        join public.orders o on o.id = oi.order_id
        where u.status = 'active'
          and u.is_active
          and o.payment_status = 'dibayar'
          and o.paid_at is not null
          and o.status <> 'dibatalkan'
        group by u.id, u.name
        order by sum(oi.unit_price * oi.quantity) desc, u.name
        limit 5
      ) leaderboard
    )
  );
end;
$$;
