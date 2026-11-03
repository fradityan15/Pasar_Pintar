create table public.seller_admin_messages (
  id bigint generated always as identity primary key,
  umkm_id uuid not null references public.umkm(id) on delete cascade,
  sender_id uuid not null,
  sender_type text not null check (sender_type in ('seller', 'admin')),
  body text not null check (char_length(trim(body)) between 1 and 2000),
  created_at timestamptz not null default now(),
  admin_read_at timestamptz,
  seller_read_at timestamptz
);

create index seller_admin_messages_thread_idx
  on public.seller_admin_messages (umkm_id, created_at, id);
create index seller_admin_messages_admin_unread_idx
  on public.seller_admin_messages (created_at desc)
  where sender_type = 'seller' and admin_read_at is null;

alter table public.seller_admin_messages enable row level security;
revoke all on public.seller_admin_messages from public, anon, authenticated;

create or replace function public.seller_send_admin_message(
  p_umkm_id uuid,
  p_body text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_message_id bigint;
  v_body text := trim(p_body);
begin
  if auth.uid() is null or not public.is_my_umkm(p_umkm_id) then
    raise exception 'Akses ditolak';
  end if;
  if v_body is null or char_length(v_body) < 1 or char_length(v_body) > 2000 then
    raise exception 'Pesan harus berisi 1 sampai 2000 karakter';
  end if;

  insert into public.seller_admin_messages (
    umkm_id, sender_id, sender_type, body, seller_read_at
  )
  values (p_umkm_id, auth.uid(), 'seller', v_body, now())
  returning id into v_message_id;
  return v_message_id;
end;
$$;

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

  update public.seller_admin_messages
  set seller_read_at = now()
  where umkm_id = p_umkm_id
    and sender_type = 'admin'
    and seller_read_at is null;

  return query
  select m.id, m.sender_type, m.body, m.created_at
  from public.seller_admin_messages m
  where m.umkm_id = p_umkm_id
  order by m.created_at, m.id;
end;
$$;

create or replace function public.admin_list_seller_message_threads()
returns table (
  thread_umkm_id uuid,
  thread_umkm_name text,
  last_message text,
  last_sender_type text,
  last_message_at timestamptz,
  unread_count bigint
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

  return query
  select u.id, u.name, latest.body, latest.sender_type, latest.created_at,
    (select count(*) from public.seller_admin_messages unread
      where unread.umkm_id = u.id
        and unread.sender_type = 'seller'
        and unread.admin_read_at is null)::bigint
  from public.umkm u
  join lateral (
    select m.body, m.sender_type, m.created_at
    from public.seller_admin_messages m
    where m.umkm_id = u.id
    order by m.created_at desc, m.id desc
    limit 1
  ) latest on true
  order by latest.created_at desc, u.name;
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

  update public.seller_admin_messages
  set admin_read_at = now()
  where umkm_id = p_umkm_id
    and sender_type = 'seller'
    and admin_read_at is null;

  return query
  select m.id, m.sender_type, m.body, m.created_at
  from public.seller_admin_messages m
  where m.umkm_id = p_umkm_id
  order by m.created_at, m.id;
end;
$$;

create or replace function public.admin_send_seller_message(
  p_umkm_id uuid,
  p_body text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_message_id bigint;
  v_body text := trim(p_body);
begin
  if not public.is_admin() then
    raise exception 'Akses ditolak';
  end if;
  if v_body is null or char_length(v_body) < 1 or char_length(v_body) > 2000 then
    raise exception 'Pesan harus berisi 1 sampai 2000 karakter';
  end if;
  if not exists (select 1 from public.umkm where id = p_umkm_id) then
    raise exception 'Toko tidak ditemukan';
  end if;

  insert into public.seller_admin_messages (
    umkm_id, sender_id, sender_type, body, admin_read_at
  )
  values (p_umkm_id, auth.uid(), 'admin', v_body, now())
  returning id into v_message_id;
  return v_message_id;
end;
$$;

revoke all on function public.seller_send_admin_message(uuid, text) from public, anon;
revoke all on function public.seller_list_admin_messages(uuid) from public, anon;
revoke all on function public.admin_list_seller_message_threads() from public, anon;
revoke all on function public.admin_list_seller_messages(uuid) from public, anon;
revoke all on function public.admin_send_seller_message(uuid, text) from public, anon;
grant execute on function public.seller_send_admin_message(uuid, text) to authenticated;
grant execute on function public.seller_list_admin_messages(uuid) to authenticated;
grant execute on function public.admin_list_seller_message_threads() to authenticated;
grant execute on function public.admin_list_seller_messages(uuid) to authenticated;
grant execute on function public.admin_send_seller_message(uuid, text) to authenticated;
