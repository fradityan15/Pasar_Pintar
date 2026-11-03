create table public.loyalty_settings (
  id boolean primary key default true check (id),
  earn_points_per_step integer not null default 1 check (earn_points_per_step > 0),
  earn_amount_step numeric(12, 0) not null default 10000 check (earn_amount_step > 0),
  redemption_value numeric(12, 0) not null default 100 check (redemption_value > 0),
  max_redeem_points_per_order integer default 100
    check (max_redeem_points_per_order is null or max_redeem_points_per_order >= 0),
  updated_at timestamptz not null default now()
);

insert into public.loyalty_settings (id) values (true);

create trigger trg_loyalty_settings_updated
  before update on public.loyalty_settings
  for each row execute function public.set_updated_at();

create table public.loyalty_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  entry_type text not null check (entry_type in ('earn', 'redeem', 'expire', 'reverse')),
  points integer not null check (points <> 0),
  order_id uuid references public.orders(id) on delete restrict,
  created_at timestamptz not null default now(),
  expires_at timestamptz,
  constraint loyalty_ledger_expiry_entry check (
    (entry_type = 'earn' and points > 0)
    or (entry_type = 'redeem' and points < 0)
    or (entry_type = 'expire' and points < 0)
    or entry_type = 'reverse'
  )
);

create unique index loyalty_ledger_order_entry_unique
  on public.loyalty_ledger (order_id, entry_type)
  where order_id is not null;
create index loyalty_ledger_user_history_idx
  on public.loyalty_ledger (user_id, created_at desc);
create index loyalty_ledger_expiry_idx
  on public.loyalty_ledger (user_id, expires_at)
  where entry_type = 'earn' and expires_at is not null;

alter table public.orders
  add column redeemed_points integer not null default 0 check (redeemed_points >= 0),
  add column points_discount numeric(12, 0) not null default 0 check (points_discount >= 0);

alter table public.loyalty_settings enable row level security;
alter table public.loyalty_ledger enable row level security;
revoke all on public.loyalty_settings, public.loyalty_ledger
  from public, anon, authenticated;
grant select on public.loyalty_settings, public.loyalty_ledger to authenticated;
grant update on public.loyalty_settings to authenticated;
grant all on public.loyalty_settings, public.loyalty_ledger to service_role;

create policy loyalty_settings_read
  on public.loyalty_settings for select to authenticated
  using (true);
create policy loyalty_settings_admin_update
  on public.loyalty_settings for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());
create policy loyalty_ledger_owner_or_admin_read
  on public.loyalty_ledger for select to authenticated
  using (user_id = (select auth.uid()) or public.is_admin());

create or replace function public.reject_loyalty_ledger_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'Buku poin bersifat append-only';
end;
$$;

create trigger loyalty_ledger_append_only
  before update or delete on public.loyalty_ledger
  for each row execute function public.reject_loyalty_ledger_mutation();

create or replace function public.create_order(
  p_address_id uuid,
  p_payment_method_id uuid,
  p_product_ids uuid[],
  p_shipping_quote_id uuid,
  p_shipping_option_id uuid,
  p_voucher_claim_id uuid,
  p_redeem_points integer
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_order_id uuid;
  v_order public.orders%rowtype;
  v_settings public.loyalty_settings%rowtype;
  v_balance bigint;
  v_points_discount numeric(12, 0);
begin
  if v_uid is null then raise exception 'Silakan login terlebih dahulu'; end if;
  if p_redeem_points is null or p_redeem_points < 0 then
    raise exception 'Jumlah penukaran poin tidak valid';
  end if;

  perform 1 from public.profiles where id = v_uid for update;
  if not found then raise exception 'Profil pelanggan tidak ditemukan'; end if;

  select * into v_settings
  from public.loyalty_settings where id = true for share;
  if not found then raise exception 'Pengaturan poin belum tersedia'; end if;

  select coalesce(sum(points), 0) into v_balance
  from public.loyalty_ledger where user_id = v_uid;
  if p_redeem_points > v_balance then
    raise exception 'Saldo poin tidak mencukupi';
  end if;
  if v_settings.max_redeem_points_per_order is not null
    and p_redeem_points > v_settings.max_redeem_points_per_order then
    raise exception 'Penukaran poin melebihi batas per pesanan';
  end if;

  v_order_id := public.create_order(
    p_address_id,
    p_payment_method_id,
    p_product_ids,
    p_shipping_quote_id,
    p_shipping_option_id,
    p_voucher_claim_id
  );
  select * into v_order from public.orders where id = v_order_id for update;
  v_points_discount := p_redeem_points * v_settings.redemption_value;
  if p_redeem_points > 0 and v_points_discount >= v_order.total then
    raise exception 'Sisakan nominal pembayaran setelah penukaran poin';
  end if;

  if p_redeem_points > 0 then
    insert into public.loyalty_ledger (user_id, entry_type, points, order_id)
    values (v_uid, 'redeem', -p_redeem_points, v_order_id);
  end if;

  update public.orders
  set redeemed_points = p_redeem_points,
    points_discount = v_points_discount,
    total = total - v_points_discount
  where id = v_order_id;

  return v_order_id;
end;
$$;

create or replace function public.award_loyalty_points_on_completion()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_settings public.loyalty_settings%rowtype;
  v_earned_points integer;
  v_eligible_amount numeric(12, 0);
begin
  if new.status <> 'selesai' or new.payment_status::text <> 'dibayar'
    or (old.status = new.status and old.payment_status::text = new.payment_status::text) then
    return new;
  end if;

  select * into v_settings from public.loyalty_settings where id = true;
  if not found then return new; end if;

  perform 1 from public.profiles where id = new.user_id for update;
  v_eligible_amount := greatest(0, new.subtotal - new.discount_amount - new.points_discount);
  v_earned_points := floor(v_eligible_amount / v_settings.earn_amount_step)
    * v_settings.earn_points_per_step;
  if v_earned_points > 0 then
    insert into public.loyalty_ledger (user_id, entry_type, points, order_id, expires_at)
    values (
      new.user_id,
      'earn',
      v_earned_points,
      new.id,
      null
    )
    on conflict (order_id, entry_type) where order_id is not null do nothing;
  end if;
  return new;
end;
$$;

create trigger orders_award_loyalty_points
  after update of status, payment_status on public.orders
  for each row execute function public.award_loyalty_points_on_completion();

create or replace function public.reverse_order_loyalty_points()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reverse_points integer;
begin
  if new.status <> 'dibatalkan' or old.status = new.status then return new; end if;

  perform 1 from public.profiles where id = new.user_id for update;
  select -coalesce(sum(points) filter (where entry_type in ('earn', 'redeem', 'expire')), 0)::integer
  into v_reverse_points
  from public.loyalty_ledger
  where user_id = new.user_id and order_id = new.id;

  if v_reverse_points <> 0 then
    insert into public.loyalty_ledger (user_id, entry_type, points, order_id)
    values (new.user_id, 'reverse', v_reverse_points, new.id)
    on conflict (order_id, entry_type) where order_id is not null do nothing;
  end if;
  return new;
end;
$$;

create trigger orders_reverse_loyalty_on_cancel
  after update of status on public.orders
  for each row execute function public.reverse_order_loyalty_points();

revoke all on function public.reject_loyalty_ledger_mutation(),
  public.award_loyalty_points_on_completion(), public.reverse_order_loyalty_points()
  from public, anon, authenticated;
revoke all on function public.create_order(uuid, uuid, uuid[], uuid, uuid, uuid, integer)
  from public, anon;
revoke all on function public.create_order(uuid, uuid, uuid[], uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.create_order(uuid, uuid, uuid[], uuid, uuid, uuid, integer)
  to authenticated;
