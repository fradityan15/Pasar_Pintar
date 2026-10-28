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
        and o.status <> 'dibatalkan'
    ),
    'total_pendapatan_platform', (
      select coalesce(sum(o.subtotal), 0)
      from public.orders o
      where o.payment_status = 'dibayar'
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
          and o.status <> 'dibatalkan'
          and coalesce(o.paid_at, o.created_at) >= (days.day::timestamp at time zone 'Asia/Jakarta')
          and coalesce(o.paid_at, o.created_at) < ((days.day + interval '1 day')::timestamp at time zone 'Asia/Jakarta')
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
          and o.status <> 'dibatalkan'
        group by u.id, u.name
        order by sum(oi.unit_price * oi.quantity) desc, u.name
        limit 5
      ) leaderboard
    )
  );
end;
$$;

revoke all on function public.admin_global_analytics() from public, anon;
grant execute on function public.admin_global_analytics() to authenticated;
