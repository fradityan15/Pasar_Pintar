-- Midtrans sandbox checkout, webhook state, and owner-readable payment status.

alter table public.payment_methods
  add column if not exists provider text not null default 'manual',
  add column if not exists provider_method text;

alter table public.payment_methods
  drop constraint if exists payment_methods_provider_check,
  add constraint payment_methods_provider_check
    check (provider in ('manual', 'midtrans')),
  drop constraint if exists payment_methods_provider_method_check,
  add constraint payment_methods_provider_method_check
    check (
      (provider = 'manual' and provider_method is null)
      or (
        provider = 'midtrans'
        and (
          (category = 'qris' and provider_method = 'qris')
          or (category = 'va' and provider_method in ('bca', 'bni', 'bri', 'mandiri', 'permata'))
        )
      )
    ),
  drop constraint if exists payment_methods_account_details_check,
  add constraint payment_methods_account_details_check
    check (
      category not in ('va', 'bank_transfer')
      or provider = 'midtrans'
      or (
        nullif(trim(account_number), '') is not null
        and nullif(trim(account_name), '') is not null
      )
    ),
  drop constraint if exists payment_methods_qr_image_check,
  add constraint payment_methods_qr_image_check
    check (category <> 'qris' or provider = 'midtrans' or nullif(trim(qr_image_url), '') is not null);

grant select (provider, provider_method) on public.payment_methods to anon, authenticated;

insert into public.payment_methods (name, category, provider, provider_method, is_active)
select seed.name, seed.category, 'midtrans', seed.provider_method, true
from (values
  ('Midtrans QRIS (Sandbox)', 'qris', 'qris'),
  ('Midtrans VA BCA (Sandbox)', 'va', 'bca'),
  ('Midtrans VA BNI (Sandbox)', 'va', 'bni'),
  ('Midtrans VA BRI (Sandbox)', 'va', 'bri'),
  ('Midtrans VA Mandiri (Sandbox)', 'va', 'mandiri'),
  ('Midtrans VA Permata (Sandbox)', 'va', 'permata')
) as seed(name, category, provider_method)
where not exists (
  select 1
  from public.payment_methods existing
  where existing.provider = 'midtrans'
    and existing.provider_method = seed.provider_method
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  provider text not null check (provider = 'midtrans'),
  provider_ref text not null,
  provider_transaction_id text,
  method text not null check (method in ('qris', 'va')),
  amount numeric(12, 0) not null check (amount > 0),
  status text not null check (status in ('creating', 'unknown', 'pending', 'paid', 'failed', 'expired', 'paid_late')),
  instructions jsonb,
  expires_at timestamptz,
  raw_payload jsonb,
  signature_valid boolean,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payments_provider_ref_unique unique (provider, provider_ref)
);

create index payments_order_created_idx on public.payments (order_id, created_at desc);
create unique index payments_midtrans_one_active_attempt_per_order
  on public.payments (order_id)
  where provider = 'midtrans' and status in ('creating', 'unknown', 'pending');

create trigger trg_payments_updated
  before update on public.payments
  for each row execute function public.set_updated_at();

alter table public.payments enable row level security;
revoke all on public.payments from public, anon, authenticated;
grant select (
  id, order_id, provider, provider_ref, provider_transaction_id, method,
  amount, status, instructions, expires_at, created_at, updated_at
) on public.payments to authenticated;
grant all on public.payments to service_role;

create policy payments_owner_read
  on public.payments for select to authenticated
  using (
    exists (
      select 1 from public.orders o
      where o.id = payments.order_id
        and o.user_id = (select auth.uid())
    )
  );

create or replace function public.begin_midtrans_payment(p_order_id uuid)
returns table (
  payment_id uuid,
  provider_ref text,
  amount numeric,
  method text,
  bank_code text,
  status text,
  instructions jsonb,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_method public.payment_methods%rowtype;
  v_payment public.payments%rowtype;
  v_payment_id uuid;
  v_provider_ref text;
  v_payment_type text;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Akses ditolak';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;
  if not found then
    raise exception 'Pesanan tidak ditemukan';
  end if;
  if v_order.status <> 'menunggu_pembayaran'
    or v_order.payment_status::text not in ('pending', 'belum_dibayar')
    or v_order.payment_expires_at is null
    or v_order.payment_expires_at <= now() then
    raise exception 'Pesanan tidak lagi menunggu pembayaran';
  end if;

  select * into v_method
  from public.payment_methods
  where id = v_order.payment_method_id
    and provider = 'midtrans'
    and is_active
  for share;
  if not found then
    raise exception 'Metode pembayaran Midtrans tidak aktif';
  end if;

  select * into v_payment
  from public.payments
  where order_id = p_order_id
    and provider = 'midtrans'
    and status in ('creating', 'unknown', 'pending')
  order by created_at desc
  limit 1
  for update;

  if found then
    return query
    select v_payment.id, v_payment.provider_ref, v_payment.amount,
      v_payment.method, v_method.provider_method, v_payment.status,
      v_payment.instructions, v_payment.expires_at;
    return;
  end if;

  v_payment_id := gen_random_uuid();
  v_provider_ref := 'PP-' || replace(v_payment_id::text, '-', '');
  v_payment_type := case v_method.category
    when 'qris' then 'qris'
    when 'va' then 'va'
    else null
  end;
  if v_payment_type is null or v_order.total <= 0 then
    raise exception 'Konfigurasi pembayaran tidak valid';
  end if;

  insert into public.payments (
    id, order_id, provider, provider_ref, method, amount, status
  )
  values (
    v_payment_id, p_order_id, 'midtrans', v_provider_ref,
    v_payment_type, v_order.total, 'creating'
  )
  returning * into v_payment;

  return query
  select v_payment.id, v_payment.provider_ref, v_payment.amount,
    v_payment.method, v_method.provider_method, v_payment.status,
    v_payment.instructions, v_payment.expires_at;
end;
$$;

create or replace function public.apply_midtrans_payment_notification(
  p_provider_ref text,
  p_transaction_id text,
  p_amount numeric,
  p_gateway_status text,
  p_paid_at timestamptz,
  p_raw_payload jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment public.payments%rowtype;
  v_order public.orders%rowtype;
  v_payment_id uuid;
  v_next_payment_status text;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Akses ditolak';
  end if;
  if p_provider_ref is null
    or p_amount is null
    or p_amount <= 0
    or p_transaction_id is null
    or p_gateway_status is null then
    raise exception 'Data notifikasi pembayaran tidak valid';
  end if;
  if p_gateway_status not in ('settlement', 'capture', 'pending', 'deny', 'cancel', 'expire') then
    raise exception 'Status pembayaran Midtrans tidak didukung';
  end if;

  select * into v_payment
  from public.payments
  where provider = 'midtrans'
    and provider_ref = p_provider_ref;
  if not found then
    raise exception 'Referensi pembayaran tidak ditemukan';
  end if;
  v_payment_id := v_payment.id;

  select * into v_order
  from public.orders
  where id = v_payment.order_id
  for update;
  if not found then
    raise exception 'Pesanan pembayaran tidak ditemukan';
  end if;

  select p.* into v_payment
  from public.payments p
  where p.id = v_payment_id
  for update;
  if not found then
    raise exception 'Referensi pembayaran tidak ditemukan';
  end if;
  if v_payment.amount <> p_amount or v_order.total <> p_amount then
    raise exception 'Pesanan atau nominal pembayaran tidak cocok';
  end if;

  if v_payment.provider_transaction_id is not null
    and p_transaction_id is not null
    and v_payment.provider_transaction_id <> p_transaction_id then
    raise exception 'ID transaksi pembayaran tidak cocok';
  end if;
  if v_payment.status in ('paid', 'paid_late') then
    return;
  end if;

  if p_gateway_status in ('settlement', 'capture') then
    if v_order.payment_status::text in ('pending', 'belum_dibayar')
      and v_order.status = 'menunggu_pembayaran'
      and (
        v_order.payment_expires_at is null
        or coalesce(p_paid_at, now()) <= v_order.payment_expires_at
      ) then
      update public.orders
      set payment_status = 'dibayar',
          status = 'menunggu_diproses',
          paid_at = coalesce(p_paid_at, now())
      where id = v_order.id;

      insert into public.order_status_logs (order_id, status, changed_by, note)
      values (v_order.id, 'menunggu_diproses', null, 'Pembayaran Midtrans terverifikasi');
      v_next_payment_status := 'paid';
    else
      -- Record a late settlement for reconciliation; never reopen a cancelled/expired order.
      v_next_payment_status := 'paid_late';
    end if;
  elsif p_gateway_status = 'expire' then
    v_next_payment_status := 'expired';
    if v_order.status = 'menunggu_pembayaran'
      and v_order.payment_status::text in ('pending', 'belum_dibayar') then
      update public.orders
      set status = 'dibatalkan',
          payment_status = 'kedaluwarsa'
      where id = v_order.id;
      perform private.restock_order(v_order.id, 'pembayaran Midtrans kedaluwarsa');
      insert into public.order_status_logs (order_id, status, changed_by, note)
      values (v_order.id, 'dibatalkan', null, 'Pembayaran Midtrans kedaluwarsa');
    end if;
  elsif p_gateway_status = 'pending' then
    v_next_payment_status := 'pending';
  else
    v_next_payment_status := 'failed';
  end if;

  update public.payments
  set status = v_next_payment_status,
      provider_transaction_id = coalesce(p_transaction_id, provider_transaction_id),
      signature_valid = true,
      raw_payload = p_raw_payload
  where id = v_payment.id;
end;
$$;

revoke all on function public.begin_midtrans_payment(uuid) from public, anon, authenticated;
revoke all on function public.apply_midtrans_payment_notification(text, text, numeric, text, timestamptz, jsonb)
  from public, anon, authenticated;
grant execute on function public.begin_midtrans_payment(uuid) to service_role;
grant execute on function public.apply_midtrans_payment_notification(text, text, numeric, text, timestamptz, jsonb)
  to service_role;
