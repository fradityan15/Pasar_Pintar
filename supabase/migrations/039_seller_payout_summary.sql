create or replace function public.seller_paid_payout_summary(p_umkm_id uuid)
returns table (
  paid_payout_total numeric,
  paid_payout_count bigint,
  last_paid_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_my_umkm(p_umkm_id) and not public.is_admin() then
    raise exception 'Akses ditolak';
  end if;

  return query
  select
    coalesce(sum(w.amount), 0)::numeric,
    count(*)::bigint,
    max(w.paid_at)
  from public.withdrawal_requests w
  where w.umkm_id = p_umkm_id
    and w.status = 'paid';
end;
$$;

revoke all on function public.seller_paid_payout_summary(uuid) from public, anon;
grant execute on function public.seller_paid_payout_summary(uuid) to authenticated;
