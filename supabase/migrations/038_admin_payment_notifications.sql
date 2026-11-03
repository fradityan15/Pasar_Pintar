create table public.admin_payment_notifications (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders(id) on delete cascade,
  order_no text not null,
  amount numeric(12, 0) not null check (amount > 0),
  payment_method text not null,
  paid_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  is_read boolean not null default false
);

create index admin_payment_notifications_created_idx
  on public.admin_payment_notifications (created_at desc);

alter table public.admin_payment_notifications enable row level security;
revoke all on public.admin_payment_notifications from public, anon, authenticated;

create or replace function public.notify_admin_of_confirmed_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_category text;
  v_method_name text;
begin
  if new.payment_status::text <> 'dibayar'
    or old.payment_status::text is not distinct from new.payment_status::text then
    return new;
  end if;

  select category, name into v_category, v_method_name
  from public.payment_methods
  where id = new.payment_method_id;

  if coalesce(v_category, '') = 'cod' or new.payment_method = 'cod' then
    return new;
  end if;

  insert into public.admin_payment_notifications (
    order_id, order_no, amount, payment_method, paid_at
  )
  values (
    new.id,
    new.order_no,
    new.total,
    coalesce(v_method_name, new.payment_method, 'Pembayaran'),
    coalesce(new.paid_at, now())
  )
  on conflict (order_id) do nothing;

  return new;
end;
$$;

create trigger orders_notify_admin_confirmed_payment
  after update of payment_status on public.orders
  for each row execute function public.notify_admin_of_confirmed_payment();

create or replace function public.admin_list_payment_notifications()
returns table (
  id uuid,
  order_id uuid,
  order_no text,
  amount numeric,
  payment_method text,
  paid_at timestamptz,
  created_at timestamptz,
  is_read boolean
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
  select n.id, n.order_id, n.order_no, n.amount, n.payment_method,
    n.paid_at, n.created_at, n.is_read
  from public.admin_payment_notifications n
  order by n.created_at desc
  limit 20;
end;
$$;

create or replace function public.admin_mark_payment_notification_read(
  p_notification_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Akses ditolak';
  end if;

  update public.admin_payment_notifications
  set is_read = true
  where id = p_notification_id;
end;
$$;

revoke all on function public.notify_admin_of_confirmed_payment() from public, anon, authenticated;
revoke all on function public.admin_list_payment_notifications() from public, anon;
revoke all on function public.admin_mark_payment_notification_read(uuid) from public, anon;
grant execute on function public.admin_list_payment_notifications() to authenticated;
grant execute on function public.admin_mark_payment_notification_read(uuid) to authenticated;
