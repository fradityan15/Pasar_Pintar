create or replace function public.seller_order_status_logs(p_order_id uuid)
returns table (
  id bigint,
  status public.order_status,
  changed_by uuid,
  note text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.order_items oi
    where oi.order_id = p_order_id
      and public.owns_active_umkm(oi.umkm_id)
  ) then
    raise exception 'Akses ditolak';
  end if;

  return query
  select l.id, l.status, l.changed_by, l.note, l.created_at
  from public.order_status_logs l
  where l.order_id = p_order_id
  order by l.created_at desc, l.id desc;
end;
$$;

revoke all on function public.seller_order_status_logs(uuid) from public, anon;
grant execute on function public.seller_order_status_logs(uuid) to authenticated;
