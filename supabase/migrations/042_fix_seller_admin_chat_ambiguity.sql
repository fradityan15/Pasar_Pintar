create or replace function public.seller_list_admin_messages(p_umkm_id uuid)
returns table (
  id bigint,
  sender_type text,
  body text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_my_umkm(p_umkm_id) then
    raise exception 'Akses ditolak';
  end if;

  update public.seller_admin_messages as message
  set seller_read_at = now()
  where message.umkm_id = p_umkm_id
    and message.sender_type = 'admin'
    and message.seller_read_at is null;

  return query
  select message.id, message.sender_type, message.body, message.created_at
  from public.seller_admin_messages as message
  where message.umkm_id = p_umkm_id
  order by message.created_at, message.id;
end;
$$;

create or replace function public.admin_list_seller_messages(p_umkm_id uuid)
returns table (
  id bigint,
  sender_type text,
  body text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Akses ditolak';
  end if;
  if not exists (select 1 from public.umkm where id = p_umkm_id) then
    raise exception 'Toko tidak ditemukan';
  end if;

  update public.seller_admin_messages as message
  set admin_read_at = now()
  where message.umkm_id = p_umkm_id
    and message.sender_type = 'seller'
    and message.admin_read_at is null;

  return query
  select message.id, message.sender_type, message.body, message.created_at
  from public.seller_admin_messages as message
  where message.umkm_id = p_umkm_id
  order by message.created_at, message.id;
end;
$$;

revoke all on function public.seller_list_admin_messages(uuid) from public, anon;
revoke all on function public.admin_list_seller_messages(uuid) from public, anon;
grant execute on function public.seller_list_admin_messages(uuid) to authenticated;
grant execute on function public.admin_list_seller_messages(uuid) to authenticated;
