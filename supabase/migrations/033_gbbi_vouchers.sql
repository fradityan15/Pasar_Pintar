-- Configurable voucher infrastructure. Program terms are intentionally not fixed here.

create table public.vouchers (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  discount_type text not null check (discount_type in ('nominal', 'persen')),
  discount_value numeric(12, 2) not null check (discount_value > 0),
  maximum_discount numeric(12, 0) check (maximum_discount is null or maximum_discount >= 0),
  minimum_purchase numeric(12, 0) not null default 0 check (minimum_purchase >= 0),
  quota_total integer check (quota_total is null or quota_total >= 0),
  quota_used integer not null default 0 check (quota_used >= 0),
  berlaku_dari timestamptz not null,
  berlaku_sampai timestamptz not null,
  is_active boolean not null default false,
  scope_type text not null default 'all' check (scope_type in ('all', 'stores', 'categories')),
  umkm_ids uuid[] not null default '{}',
  category_ids uuid[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vouchers_valid_period check (berlaku_sampai > berlaku_dari),
  constraint vouchers_quota_not_over_limit check (quota_total is null or quota_used <= quota_total),
  constraint vouchers_discount_value_valid check (
    (discount_type = 'nominal' and discount_value = trunc(discount_value))
    or (discount_type = 'persen' and discount_value <= 100)
  ),
  constraint vouchers_scope_values_valid check (
    (scope_type = 'all' and cardinality(umkm_ids) = 0 and cardinality(category_ids) = 0)
    or (scope_type = 'stores' and cardinality(umkm_ids) > 0 and cardinality(category_ids) = 0)
    or (scope_type = 'categories' and cardinality(category_ids) > 0 and cardinality(umkm_ids) = 0)
  )
);

create unique index vouchers_code_upper_unique on public.vouchers (upper(code));
create index vouchers_active_period_idx on public.vouchers (is_active, berlaku_dari, berlaku_sampai);
create trigger trg_vouchers_updated
  before update on public.vouchers
  for each row execute function public.set_updated_at();

create table public.voucher_claims (
  id uuid primary key default gen_random_uuid(),
  voucher_id uuid not null references public.vouchers(id) on delete restrict,
  user_id uuid not null references public.profiles(id) on delete cascade,
  order_id uuid references public.orders(id) on delete set null,
  status text not null default 'claimed' check (status in ('claimed', 'used', 'expired')),
  claimed_at timestamptz not null default now(),
  used_at timestamptz,
  constraint voucher_claims_user_unique unique (voucher_id, user_id)
);

create unique index voucher_claims_order_unique
  on public.voucher_claims (order_id) where order_id is not null;
create index voucher_claims_user_claimed_idx
  on public.voucher_claims (user_id, claimed_at desc);
create index voucher_claims_voucher_status_idx
  on public.voucher_claims (voucher_id, status);

alter table public.orders
  add column voucher_id uuid references public.vouchers(id) on delete set null,
  add column discount_amount numeric(12, 0) not null default 0
    check (discount_amount >= 0);

alter table public.order_items
  add column category_id uuid;

create or replace function public.snapshot_order_item_category()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.product_id is not null and new.category_id is null then
    select p.category_id into new.category_id
    from public.products p
    where p.id = new.product_id;
  end if;
  return new;
end;
$$;

create trigger order_items_snapshot_category
  before insert on public.order_items
  for each row execute function public.snapshot_order_item_category();

alter table public.vouchers enable row level security;
alter table public.voucher_claims enable row level security;
revoke all on public.vouchers, public.voucher_claims from public, anon, authenticated;
grant select on public.vouchers to authenticated;
grant insert, update, delete on public.vouchers to authenticated;
grant select on public.voucher_claims to authenticated;

create policy vouchers_active_read
  on public.vouchers for select to authenticated
  using (
    public.is_admin()
    or (
      is_active
      and berlaku_dari <= now()
      and berlaku_sampai > now()
      and (quota_total is null or quota_used < quota_total)
    )
  );
create policy vouchers_admin_insert
  on public.vouchers for insert to authenticated
  with check (public.is_admin());
create policy vouchers_admin_update
  on public.vouchers for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());
create policy vouchers_admin_delete
  on public.vouchers for delete to authenticated
  using (public.is_admin());

create policy voucher_claims_owner_or_admin_read
  on public.voucher_claims for select to authenticated
  using (user_id = (select auth.uid()) or public.is_admin());

create or replace function public.claim_voucher(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_voucher public.vouchers%rowtype;
  v_claim public.voucher_claims%rowtype;
begin
  if v_uid is null then raise exception 'Silakan login untuk mengklaim voucher'; end if;
  if nullif(trim(p_code), '') is null then raise exception 'Masukkan kode voucher'; end if;

  select * into v_voucher
  from public.vouchers
  where upper(code) = upper(trim(p_code))
  for update;
  if not found then raise exception 'Kode voucher tidak ditemukan'; end if;

  select * into v_claim
  from public.voucher_claims
  where voucher_id = v_voucher.id and user_id = v_uid;
  if found then
    if v_claim.status = 'claimed' and v_claim.order_id is null
      and v_voucher.is_active
      and v_voucher.berlaku_dari <= now()
      and v_voucher.berlaku_sampai > now() then
      return jsonb_build_object(
        'claim_id', v_claim.id, 'voucher_id', v_voucher.id, 'code', v_voucher.code,
        'discount_type', v_voucher.discount_type, 'discount_value', v_voucher.discount_value,
        'maximum_discount', v_voucher.maximum_discount, 'minimum_purchase', v_voucher.minimum_purchase,
        'scope_type', v_voucher.scope_type, 'umkm_ids', v_voucher.umkm_ids,
        'category_ids', v_voucher.category_ids, 'berlaku_sampai', v_voucher.berlaku_sampai,
        'status', v_claim.status
      );
    end if;
    raise exception 'Voucher ini sudah pernah diklaim oleh akun Anda';
  end if;
  if not v_voucher.is_active or v_voucher.berlaku_dari > now()
    or v_voucher.berlaku_sampai <= now() then
    raise exception 'Voucher belum berlaku atau sudah kedaluwarsa';
  end if;
  if v_voucher.quota_total is not null and v_voucher.quota_used >= v_voucher.quota_total then
    raise exception 'Kuota voucher sudah habis';
  end if;

  update public.vouchers
  set quota_used = quota_used + 1
  where id = v_voucher.id
    and (quota_total is null or quota_used < quota_total);
  if not found then raise exception 'Kuota voucher sudah habis'; end if;

  insert into public.voucher_claims (voucher_id, user_id)
  values (v_voucher.id, v_uid)
  returning * into v_claim;

  return jsonb_build_object(
    'claim_id', v_claim.id,
    'voucher_id', v_voucher.id,
    'code', v_voucher.code,
    'discount_type', v_voucher.discount_type,
    'discount_value', v_voucher.discount_value,
    'maximum_discount', v_voucher.maximum_discount,
    'minimum_purchase', v_voucher.minimum_purchase,
    'scope_type', v_voucher.scope_type,
    'umkm_ids', v_voucher.umkm_ids,
    'category_ids', v_voucher.category_ids,
    'berlaku_sampai', v_voucher.berlaku_sampai,
    'status', v_claim.status
  );
end;
$$;

create or replace function public.my_voucher_claims()
returns table (
  claim_id uuid,
  voucher_id uuid,
  code text,
  discount_type text,
  discount_value numeric,
  maximum_discount numeric,
  minimum_purchase numeric,
  scope_type text,
  umkm_ids uuid[],
  category_ids uuid[],
  berlaku_dari timestamptz,
  berlaku_sampai timestamptz,
  claim_status text,
  claimed_at timestamptz,
  used_at timestamptz,
  order_id uuid
)
language sql
stable
security definer
set search_path = public
as $$
  select c.id, v.id, v.code, v.discount_type, v.discount_value, v.maximum_discount,
    v.minimum_purchase, v.scope_type, v.umkm_ids, v.category_ids, v.berlaku_dari, v.berlaku_sampai,
    case
      when c.status = 'claimed' and c.order_id is null and v.berlaku_sampai <= now()
        then 'expired'
      else c.status
    end, c.claimed_at, c.used_at, c.order_id
  from public.voucher_claims c
  join public.vouchers v on v.id = c.voucher_id
  where c.user_id = auth.uid()
  order by c.claimed_at desc;
$$;

create or replace function public.release_order_voucher_claim()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_voucher_id uuid;
begin
  if new.status <> 'dibatalkan'
    and new.payment_status::text <> 'kedaluwarsa' then
    return new;
  end if;
  if old.status = new.status and old.payment_status::text = new.payment_status::text then
    return new;
  end if;

  update public.voucher_claims
  set status = 'expired'
  where order_id = new.id and status = 'used'
  returning voucher_id into v_voucher_id;
  if v_voucher_id is not null then
    update public.vouchers
    set quota_used = greatest(0, quota_used - 1)
    where id = v_voucher_id;
  end if;
  return new;
end;
$$;

create trigger orders_release_voucher_claim
  after update of status, payment_status on public.orders
  for each row execute function public.release_order_voucher_claim();

create or replace function public.expire_unattached_voucher_claims()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_voucher record;
  v_claim record;
  v_count integer := 0;
  v_expired_for_voucher integer;
begin
  if auth.role() is not null and auth.role() <> 'service_role'
    and not public.is_admin() then
    raise exception 'Akses ditolak';
  end if;
  for v_voucher in
    select id from public.vouchers
    where berlaku_sampai <= now()
    order by id
    for update skip locked
  loop
    v_expired_for_voucher := 0;
    for v_claim in
      select id
      from public.voucher_claims
      where voucher_id = v_voucher.id and status = 'claimed' and order_id is null
      order by id
      for update skip locked
    loop
      update public.voucher_claims set status = 'expired'
      where id = v_claim.id and status = 'claimed';
      if found then
        v_count := v_count + 1;
        v_expired_for_voucher := v_expired_for_voucher + 1;
      end if;
    end loop;
    if v_expired_for_voucher > 0 then
      update public.vouchers
      set quota_used = greatest(0, quota_used - v_expired_for_voucher)
      where id = v_voucher.id;
    end if;
  end loop;
  return v_count;
end;
$$;

create or replace function public.create_order(
  p_address_id uuid,
  p_payment_method_id uuid,
  p_product_ids uuid[],
  p_shipping_quote_id uuid,
  p_shipping_option_id uuid,
  p_voucher_claim_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_voucher_id uuid;
  v_voucher public.vouchers%rowtype;
  v_claim public.voucher_claims%rowtype;
  v_order_id uuid;
  v_eligible_subtotal numeric(12, 0);
  v_discount numeric(12, 0);
begin
  if v_uid is null then raise exception 'Silakan login terlebih dahulu'; end if;
  if p_voucher_claim_id is not null then
    select voucher_id into v_voucher_id
    from public.voucher_claims
    where id = p_voucher_claim_id and user_id = v_uid;
    if not found then raise exception 'Klaim voucher tidak ditemukan'; end if;

    select * into v_voucher
    from public.vouchers
    where id = v_voucher_id
    for update;
    if not found or not v_voucher.is_active
      or v_voucher.berlaku_dari > now() or v_voucher.berlaku_sampai <= now() then
      raise exception 'Voucher belum berlaku atau sudah kedaluwarsa';
    end if;

    select * into v_claim
    from public.voucher_claims
    where id = p_voucher_claim_id and user_id = v_uid
    for update;
    if not found or v_claim.status <> 'claimed' or v_claim.order_id is not null then
      raise exception 'Klaim voucher sudah digunakan atau tidak tersedia';
    end if;
  end if;

  v_order_id := public.create_order(
    p_address_id,
    p_payment_method_id,
    p_product_ids,
    p_shipping_quote_id,
    p_shipping_option_id
  );

  if p_voucher_claim_id is not null then
    select coalesce(sum(oi.unit_price * oi.quantity), 0)::numeric(12, 0)
    into v_eligible_subtotal
    from public.order_items oi
    where oi.order_id = v_order_id
      and (
        v_voucher.scope_type = 'all'
        or (v_voucher.scope_type = 'stores' and oi.umkm_id = any(v_voucher.umkm_ids))
        or (v_voucher.scope_type = 'categories' and oi.category_id = any(v_voucher.category_ids))
      );
    if v_eligible_subtotal < v_voucher.minimum_purchase then
      raise exception 'Subtotal produk yang memenuhi syarat voucher belum mencapai minimum belanja';
    end if;
    if v_eligible_subtotal <= 0 then
      raise exception 'Voucher tidak berlaku untuk produk dalam pesanan ini';
    end if;

    if v_voucher.discount_type = 'nominal' then
      v_discount := least(v_voucher.discount_value, v_eligible_subtotal);
    else
      v_discount := round(v_eligible_subtotal * v_voucher.discount_value / 100);
      if v_voucher.maximum_discount is not null then
        v_discount := least(v_discount, v_voucher.maximum_discount);
      end if;
      v_discount := least(v_discount, v_eligible_subtotal);
    end if;

    update public.orders
    set voucher_id = v_voucher.id,
      discount_amount = v_discount,
      total = subtotal + shipping_cost - v_discount
    where id = v_order_id;
    update public.voucher_claims
    set status = 'used', order_id = v_order_id, used_at = now()
    where id = p_voucher_claim_id;
  end if;

  return v_order_id;
end;
$$;

revoke all on function public.create_order(uuid, uuid, uuid[], uuid, uuid, uuid)
  from public, anon;
revoke all on function public.create_order(uuid, uuid, uuid[], uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.create_order(uuid, uuid, uuid[], uuid, uuid, uuid)
  to authenticated;

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
    with seller_totals as (
      select oi.umkm_id,
        sum(oi.unit_price * oi.quantity)::numeric(12, 0) as gross_amount,
        coalesce(sum(oi.unit_price * oi.quantity) filter (
          where v.id is null
            or v.scope_type = 'all'
            or (v.scope_type = 'stores' and oi.umkm_id = any(v.umkm_ids))
            or (v.scope_type = 'categories' and oi.category_id = any(v.category_ids))
        ), 0)::numeric(12, 0) as eligible_amount
      from public.order_items oi
      left join public.vouchers v on v.id = v_order.voucher_id
      where oi.order_id = p_order_id and oi.umkm_id is not null
      group by oi.umkm_id
    ),
    totals as (
      select coalesce(sum(eligible_amount), 0)::numeric(12, 0) as eligible_total
      from seller_totals
    ),
    shares as (
      select s.*,
        case when t.eligible_total > 0
          then round(v_order.discount_amount * s.eligible_amount / t.eligible_total)
          else 0 end::numeric(12, 0) as rounded_share,
        row_number() over (order by (s.eligible_amount > 0), s.umkm_id) as row_num,
        count(*) over () as row_count,
        t.eligible_total
      from seller_totals s cross join totals t
    ),
    allocations as (
      select shares.*,
        case when row_num = row_count and eligible_total > 0
          then v_order.discount_amount
            - coalesce(sum(rounded_share) over (
              order by (eligible_amount > 0), umkm_id
              rows between unbounded preceding and 1 preceding
            ), 0)
          else rounded_share end as discount_share
      from shares
    )
    select umkm_id, gross_amount - discount_share as amount
    from allocations
    where gross_amount - discount_share > 0
    order by umkm_id
  loop
    insert into public.escrow_holds (order_id, umkm_id, amount)
    values (p_order_id, v_item.umkm_id, v_item.amount)
    on conflict (order_id, umkm_id) do nothing;
    if found then v_inserted := v_inserted + 1; end if;
  end loop;
  return v_inserted;
end;
$$;

revoke all on function public.claim_voucher(text), public.my_voucher_claims(),
  public.expire_unattached_voucher_claims(), public.snapshot_order_item_category(),
  public.release_order_voucher_claim() from public, anon;
revoke all on function public.expire_unattached_voucher_claims() from authenticated;
grant execute on function public.claim_voucher(text), public.my_voucher_claims()
  to authenticated;
grant execute on function public.expire_unattached_voucher_claims()
  to service_role;
grant execute on function public.hold_escrow(uuid)
  to authenticated, service_role;

do $cron$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron')
    and not exists (select 1 from cron.job where jobname = 'expire-unattached-voucher-claims') then
    perform cron.schedule(
      'expire-unattached-voucher-claims',
      '*/15 * * * *',
      $job$select public.expire_unattached_voucher_claims();$job$
    );
  end if;
end;
$cron$;
