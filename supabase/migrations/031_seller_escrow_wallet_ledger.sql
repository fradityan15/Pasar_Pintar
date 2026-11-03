-- Internal capstone ledger only. This migration does not move real funds.

create table public.platform_financial_settings (
  id boolean primary key default true check (id),
  commission_percent numeric(5, 2) not null default 10
    check (commission_percent >= 0 and commission_percent <= 100),
  auto_confirm_days integer not null default 7
    check (auto_confirm_days between 1 and 90),
  updated_at timestamptz not null default now()
);

insert into public.platform_financial_settings (id, commission_percent, auto_confirm_days)
values (true, 10, 7)
on conflict (id) do nothing;

alter table public.platform_financial_settings enable row level security;
revoke all on public.platform_financial_settings from public, anon, authenticated;
grant select on public.platform_financial_settings to authenticated;
create policy platform_financial_settings_admin_read
  on public.platform_financial_settings for select to authenticated
  using (public.is_admin());

create table public.escrow_holds (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete restrict,
  umkm_id uuid not null references public.umkm(id) on delete restrict,
  amount numeric(12, 0) not null check (amount > 0),
  status text not null default 'held' check (status in ('held', 'released', 'refunded')),
  held_at timestamptz not null default now(),
  released_at timestamptz,
  created_at timestamptz not null default now(),
  constraint escrow_holds_order_umkm_unique unique (order_id, umkm_id)
);

create index escrow_holds_umkm_status_idx on public.escrow_holds (umkm_id, status);
create index escrow_holds_order_idx on public.escrow_holds (order_id);

create table public.withdrawal_requests (
  id uuid primary key default gen_random_uuid(),
  umkm_id uuid not null references public.umkm(id) on delete restrict,
  amount numeric(12, 0) not null check (amount > 0),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'paid')),
  bank_snapshot jsonb not null,
  idempotency_key uuid not null,
  admin_note text,
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  paid_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint withdrawal_requests_umkm_key_unique unique (umkm_id, idempotency_key)
);

create index withdrawal_requests_status_idx on public.withdrawal_requests (status, requested_at);
create index withdrawal_requests_umkm_idx on public.withdrawal_requests (umkm_id, requested_at desc);
create trigger trg_withdrawal_requests_updated
  before update on public.withdrawal_requests
  for each row execute function public.set_updated_at();

create table public.wallet_ledger (
  id bigint generated always as identity primary key,
  umkm_id uuid not null references public.umkm(id) on delete restrict,
  entry_type text not null check (entry_type in (
    'sale_credit', 'commission_debit', 'withdrawal_debit',
    'withdrawal_reversal', 'refund_debit', 'escrow_refund'
  )),
  amount numeric(12, 0) not null,
  order_id uuid references public.orders(id) on delete restrict,
  withdrawal_id uuid references public.withdrawal_requests(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint wallet_ledger_entry_amount_check check (
    (entry_type in ('sale_credit', 'withdrawal_reversal') and amount > 0)
    or (entry_type in ('commission_debit', 'withdrawal_debit', 'refund_debit') and amount < 0)
    or (entry_type = 'escrow_refund' and amount > 0)
  ),
  constraint wallet_ledger_order_entry_check check (
    (entry_type in ('sale_credit', 'commission_debit', 'refund_debit', 'escrow_refund')
      and order_id is not null and withdrawal_id is null)
    or (entry_type in ('withdrawal_debit', 'withdrawal_reversal')
      and withdrawal_id is not null and order_id is null)
  )
);

create unique index wallet_ledger_order_entries_unique
  on public.wallet_ledger (umkm_id, order_id, entry_type)
  where order_id is not null;
create unique index wallet_ledger_withdrawal_entries_unique
  on public.wallet_ledger (umkm_id, withdrawal_id, entry_type)
  where withdrawal_id is not null;
create index wallet_ledger_umkm_created_idx on public.wallet_ledger (umkm_id, created_at desc);

create or replace function private.reject_wallet_ledger_mutation()
returns trigger
language plpgsql
set search_path = public, private
as $$
begin
  raise exception 'wallet_ledger bersifat append-only';
end;
$$;

create trigger wallet_ledger_append_only
  before update or delete on public.wallet_ledger
  for each row execute function private.reject_wallet_ledger_mutation();

alter table public.escrow_holds enable row level security;
alter table public.wallet_ledger enable row level security;
alter table public.withdrawal_requests enable row level security;
revoke all on public.escrow_holds, public.wallet_ledger, public.withdrawal_requests
  from public, anon, authenticated;
grant select on public.escrow_holds, public.wallet_ledger, public.withdrawal_requests to authenticated;
revoke all on public.escrow_holds, public.wallet_ledger, public.withdrawal_requests
  from service_role;

create policy escrow_holds_seller_read on public.escrow_holds for select to authenticated
  using (public.is_my_umkm(umkm_id) or public.is_admin());
create policy wallet_ledger_seller_read on public.wallet_ledger for select to authenticated
  using (public.is_my_umkm(umkm_id) or public.is_admin());
create policy withdrawal_requests_seller_read on public.withdrawal_requests for select to authenticated
  using (public.is_my_umkm(umkm_id) or public.is_admin());

create or replace function public.hold_escrow(p_order_id uuid)
returns integer
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_order public.orders%rowtype;
  v_inserted integer := 0;
  v_item record;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.payment_status::text <> 'dibayar' then
    raise exception 'Escrow hanya dapat ditahan setelah pembayaran terkonfirmasi';
  end if;
  if auth.role() is not null and auth.role() <> 'service_role'
    and not public.is_admin()
    and not (v_order.user_id = auth.uid() and v_order.status = 'selesai') then
    raise exception 'Akses ditolak';
  end if;

  for v_item in
    select oi.umkm_id, sum(oi.unit_price * oi.quantity)::numeric(12, 0) as amount
    from public.order_items oi
    where oi.order_id = p_order_id and oi.umkm_id is not null
    group by oi.umkm_id
  loop
    insert into public.escrow_holds (order_id, umkm_id, amount)
    values (p_order_id, v_item.umkm_id, v_item.amount)
    on conflict (order_id, umkm_id) do nothing;
    if found then v_inserted := v_inserted + 1; end if;
  end loop;
  return v_inserted;
end;
$$;

create or replace function public.release_escrow(p_order_id uuid)
returns integer
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_order public.orders%rowtype;
  v_hold public.escrow_holds%rowtype;
  v_commission_percent numeric(5, 2);
  v_fee numeric(12, 0);
  v_net numeric(12, 0);
  v_released integer := 0;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.status <> 'selesai' or v_order.payment_status::text <> 'dibayar' then
    raise exception 'Escrow hanya dapat dirilis untuk pesanan selesai dan lunas';
  end if;
  if auth.role() is not null and auth.role() <> 'service_role'
    and not public.is_admin()
    and v_order.user_id <> auth.uid() then
    raise exception 'Akses ditolak';
  end if;

  perform public.hold_escrow(p_order_id);
  select commission_percent into v_commission_percent
  from public.platform_financial_settings where id = true for share;

  for v_hold in
    select * from public.escrow_holds
    where order_id = p_order_id and status = 'held'
    order by umkm_id
    for update
  loop
    perform 1 from public.umkm where id = v_hold.umkm_id for update;
    v_fee := round(v_hold.amount * v_commission_percent / 100)::numeric(12, 0);
    v_net := v_hold.amount - v_fee;
    update public.escrow_holds
    set status = 'released', released_at = now()
    where id = v_hold.id and status = 'held';
    if found then
      insert into public.wallet_ledger (umkm_id, entry_type, amount, order_id)
      values (v_hold.umkm_id, 'sale_credit', v_hold.amount, p_order_id)
      on conflict do nothing;
      if v_fee > 0 then
        insert into public.wallet_ledger (umkm_id, entry_type, amount, order_id)
        values (v_hold.umkm_id, 'commission_debit', -v_fee, p_order_id)
        on conflict do nothing;
      end if;
      v_released := v_released + 1;
    end if;
  end loop;
  return v_released;
end;
$$;

create or replace function public.refund_escrow(p_order_id uuid)
returns integer
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_order public.orders%rowtype;
  v_hold public.escrow_holds%rowtype;
  v_released_net numeric(12, 0);
  v_count integer := 0;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.status <> 'dibatalkan' then
    raise exception 'Refund escrow hanya dapat dilakukan setelah pesanan dibatalkan';
  end if;
  if auth.role() is not null and auth.role() <> 'service_role' and not public.is_admin()
    and v_order.user_id <> auth.uid() then
    raise exception 'Akses ditolak';
  end if;

  for v_hold in
    select * from public.escrow_holds
    where order_id = p_order_id and status in ('held', 'released')
    order by umkm_id
    for update
  loop
    perform 1 from public.umkm where id = v_hold.umkm_id for update;
    if v_hold.status = 'released' then
      select coalesce(sum(amount), 0)::numeric(12, 0) into v_released_net
      from public.wallet_ledger
      where umkm_id = v_hold.umkm_id and order_id = p_order_id
        and entry_type in ('sale_credit', 'commission_debit');
      if v_released_net > 0 then
        insert into public.wallet_ledger (umkm_id, entry_type, amount, order_id)
        values (v_hold.umkm_id, 'refund_debit', -v_released_net, p_order_id)
        on conflict do nothing;
      end if;
    end if;
    insert into public.wallet_ledger (umkm_id, entry_type, amount, order_id)
    values (v_hold.umkm_id, 'escrow_refund', v_hold.amount, p_order_id)
    on conflict do nothing;
    update public.escrow_holds set status = 'refunded' where id = v_hold.id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

create or replace function public.seller_wallet_summary(p_umkm_id uuid)
returns table (held_balance numeric, available_balance numeric)
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
    coalesce((select sum(e.amount) from public.escrow_holds e
      where e.umkm_id = p_umkm_id and e.status = 'held'), 0)::numeric,
    coalesce((select sum(l.amount) from public.wallet_ledger l
      where l.umkm_id = p_umkm_id
        and l.entry_type in ('sale_credit', 'commission_debit', 'withdrawal_debit',
          'withdrawal_reversal', 'refund_debit')), 0)::numeric;
end;
$$;

create or replace function public.request_withdrawal(
  p_amount numeric,
  p_idempotency_key uuid default gen_random_uuid()
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_umkm public.umkm%rowtype;
  v_existing public.withdrawal_requests%rowtype;
  v_available numeric(12, 0);
  v_withdrawal_id uuid;
begin
  if auth.uid() is null or p_amount is null or p_amount <= 0
    or p_amount <> trunc(p_amount) or p_idempotency_key is null then
    raise exception 'Jumlah penarikan tidak valid';
  end if;
  select * into v_umkm from public.umkm
  where user_id = auth.uid() for update;
  if not found or v_umkm.status <> 'active' or not v_umkm.is_active then
    raise exception 'Toko aktif tidak ditemukan';
  end if;

  select * into v_existing from public.withdrawal_requests
  where umkm_id = v_umkm.id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.amount <> p_amount then
      raise exception 'Kunci idempotensi sudah digunakan untuk jumlah berbeda';
    end if;
    return v_existing.id;
  end if;
  if nullif(trim(v_umkm.bank_name), '') is null
    or nullif(trim(v_umkm.bank_account_number), '') is null
    or nullif(trim(v_umkm.bank_account_holder), '') is null then
    raise exception 'Lengkapi rekening penarikan pada pengaturan toko';
  end if;

  select coalesce(sum(amount), 0)::numeric(12, 0) into v_available
  from public.wallet_ledger
  where umkm_id = v_umkm.id
    and entry_type in ('sale_credit', 'commission_debit', 'withdrawal_debit',
      'withdrawal_reversal', 'refund_debit');
  if p_amount > v_available then
    raise exception 'Saldo tersedia tidak mencukupi';
  end if;

  insert into public.withdrawal_requests (
    umkm_id, amount, bank_snapshot, idempotency_key
  ) values (
    v_umkm.id, p_amount,
    jsonb_build_object(
      'bank_name', v_umkm.bank_name,
      'account_number', v_umkm.bank_account_number,
      'account_holder', v_umkm.bank_account_holder
    ),
    p_idempotency_key
  ) returning id into v_withdrawal_id;
  insert into public.wallet_ledger (umkm_id, entry_type, amount, withdrawal_id)
  values (v_umkm.id, 'withdrawal_debit', -p_amount, v_withdrawal_id);
  return v_withdrawal_id;
end;
$$;

create or replace function public.admin_process_withdrawal(
  p_withdrawal_id uuid,
  p_decision text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.withdrawal_requests%rowtype;
begin
  if not public.is_admin() then raise exception 'Akses ditolak'; end if;
  select * into v_request from public.withdrawal_requests
  where id = p_withdrawal_id for update;
  if not found then raise exception 'Permintaan penarikan tidak ditemukan'; end if;

  if p_decision = v_request.status then return; end if;
  if p_decision = 'approved' and v_request.status = 'pending' then
    update public.withdrawal_requests
    set status = 'approved', admin_note = nullif(trim(p_note), ''), reviewed_at = now()
    where id = p_withdrawal_id;
  elsif p_decision = 'rejected' and v_request.status = 'pending' then
    update public.withdrawal_requests
    set status = 'rejected', admin_note = nullif(trim(p_note), ''), reviewed_at = now()
    where id = p_withdrawal_id;
    insert into public.wallet_ledger (umkm_id, entry_type, amount, withdrawal_id)
    values (v_request.umkm_id, 'withdrawal_reversal', v_request.amount, v_request.id)
    on conflict do nothing;
  elsif p_decision = 'paid' and v_request.status = 'approved' then
    update public.withdrawal_requests
    set status = 'paid', admin_note = coalesce(nullif(trim(p_note), ''), admin_note),
      paid_at = now()
    where id = p_withdrawal_id;
  else
    raise exception 'Transisi status penarikan tidak valid';
  end if;
end;
$$;

create or replace function public.admin_update_financial_settings(
  p_commission_percent numeric,
  p_auto_confirm_days integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'Akses ditolak'; end if;
  if p_commission_percent is null or p_commission_percent < 0 or p_commission_percent > 100
    or p_auto_confirm_days is null or p_auto_confirm_days < 1 or p_auto_confirm_days > 90 then
    raise exception 'Pengaturan komisi atau masa konfirmasi tidak valid';
  end if;
  update public.platform_financial_settings
  set commission_percent = p_commission_percent,
    auto_confirm_days = p_auto_confirm_days,
    updated_at = now()
  where id = true;
end;
$$;

create or replace function public.admin_list_withdrawals()
returns table (
  id uuid, umkm_id uuid, umkm_name text, amount numeric, status text,
  bank_snapshot jsonb, admin_note text, requested_at timestamptz,
  reviewed_at timestamptz, paid_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'Akses ditolak'; end if;
  return query
  select w.id, w.umkm_id, u.name, w.amount, w.status, w.bank_snapshot,
    w.admin_note, w.requested_at, w.reviewed_at, w.paid_at
  from public.withdrawal_requests w
  join public.umkm u on u.id = w.umkm_id
  order by case w.status when 'pending' then 0 when 'approved' then 1 else 2 end,
    w.requested_at desc;
end;
$$;

create or replace function public.confirm_order_received(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_order public.orders%rowtype;
  v_payment_category text;
begin
  if auth.uid() is null then raise exception 'Anda harus masuk untuk mengonfirmasi pesanan'; end if;
  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.user_id <> auth.uid() then raise exception 'Pesanan tidak ditemukan'; end if;
  if v_order.status <> 'dikirim' then raise exception 'Pesanan hanya dapat dikonfirmasi setelah dikirim'; end if;

  select category into v_payment_category from public.payment_methods
  where id = v_order.payment_method_id;
  v_payment_category := coalesce(v_payment_category, case when v_order.payment_method = 'cod' then 'cod' end);

  update public.orders
  set status = 'selesai',
    payment_status = case when v_payment_category = 'cod' then 'dibayar' else payment_status end,
    paid_at = case when v_payment_category = 'cod' then coalesce(paid_at, now()) else paid_at end
  where id = p_order_id;
  insert into public.order_status_logs (order_id, status, changed_by, note)
  values (p_order_id, 'selesai', auth.uid(),
    case when v_payment_category = 'cod'
      then 'Pesanan COD diterima dan pembayaran dikonfirmasi oleh pembeli'
      else 'Penerimaan barang dikonfirmasi oleh pembeli' end);
  perform public.hold_escrow(p_order_id);
  perform public.release_escrow(p_order_id);
end;
$$;

create or replace function public.cancel_order(p_order_id uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_order public.orders%rowtype;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if auth.uid() is null or not found or v_order.user_id <> auth.uid() or public.is_admin() then
    raise exception 'Pesanan tidak ditemukan';
  end if;
  if not (
    v_order.status = 'menunggu_pembayaran'
    or (v_order.status in ('menunggu_diproses', 'diproses')
      and exists (select 1 from public.order_items where order_id = p_order_id)
      and not exists (select 1 from public.order_items
        where order_id = p_order_id and seller_shipping_status <> 'menunggu_diproses'))
  ) then raise exception 'Pesanan tidak dapat dibatalkan pada status ini'; end if;

  update public.orders set status = 'dibatalkan' where id = p_order_id;
  perform private.restock_order(p_order_id, coalesce(p_reason, 'pesanan dibatalkan'));
  insert into public.order_status_logs (order_id, status, changed_by, note)
  values (p_order_id, 'dibatalkan', auth.uid(), coalesce(p_reason, 'Pesanan dibatalkan oleh pembeli'));
  if v_order.payment_status::text = 'dibayar' then
    perform public.refund_escrow(p_order_id);
  end if;
end;
$$;

create or replace function public.process_due_order_auto_confirm()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_days integer;
  v_order record;
  v_count integer := 0;
begin
  if auth.role() is not null and auth.role() <> 'service_role' then raise exception 'Akses ditolak'; end if;
  select auto_confirm_days into v_days from public.platform_financial_settings where id = true;
  for v_order in
    select o.id
    from public.orders o
    where o.status = 'dikirim' and o.payment_status::text = 'dibayar'
      and (select max(l.created_at) from public.order_status_logs l
        where l.order_id = o.id and l.status = 'dikirim') <= now() - make_interval(days => v_days)
    order by o.id
    for update of o skip locked
  loop
    update public.orders set status = 'selesai' where id = v_order.id and status = 'dikirim';
    if found then
      insert into public.order_status_logs (order_id, status, changed_by, note)
      values (v_order.id, 'selesai', null, 'Konfirmasi penerimaan otomatis setelah masa perlindungan pembeli');
      perform public.release_escrow(v_order.id);
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;

create or replace function public.record_order_payment_for_escrow()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.payment_status::text = 'dibayar'
    and old.payment_status::text is distinct from new.payment_status::text then
    perform public.hold_escrow(new.id);
  end if;
  return new;
end;
$$;

create trigger orders_hold_escrow_after_payment
  after update of payment_status on public.orders
  for each row execute function public.record_order_payment_for_escrow();

create or replace function public.record_order_cancellation_refund()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'dibatalkan'
    and old.status is distinct from new.status
    and new.payment_status::text = 'dibayar' then
    perform public.refund_escrow(new.id);
  end if;
  return new;
end;
$$;

create trigger orders_refund_escrow_after_cancel
  after update of status on public.orders
  for each row execute function public.record_order_cancellation_refund();

revoke all on function public.hold_escrow(uuid), public.release_escrow(uuid),
  public.refund_escrow(uuid), public.seller_wallet_summary(uuid),
  public.request_withdrawal(numeric, uuid), public.admin_process_withdrawal(uuid, text, text),
  public.admin_update_financial_settings(numeric, integer), public.admin_list_withdrawals(), public.process_due_order_auto_confirm(),
  public.record_order_payment_for_escrow(), public.record_order_cancellation_refund()
  from public, anon;
revoke all on function public.hold_escrow(uuid), public.release_escrow(uuid),
  public.refund_escrow(uuid), public.process_due_order_auto_confirm()
  from authenticated;
grant execute on function public.hold_escrow(uuid), public.release_escrow(uuid),
  public.refund_escrow(uuid), public.seller_wallet_summary(uuid),
  public.request_withdrawal(numeric, uuid), public.admin_process_withdrawal(uuid, text, text),
  public.admin_update_financial_settings(numeric, integer), public.admin_list_withdrawals()
  to authenticated;
grant execute on function public.hold_escrow(uuid), public.release_escrow(uuid),
  public.refund_escrow(uuid), public.process_due_order_auto_confirm()
  to service_role;

do $cron$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if not exists (select 1 from cron.job where jobname = 'auto-confirm-delivered-orders') then
      perform cron.schedule(
        'auto-confirm-delivered-orders',
        '15 * * * *',
        $job$select public.process_due_order_auto_confirm();$job$
      );
    end if;
  end if;
end;
$cron$;
