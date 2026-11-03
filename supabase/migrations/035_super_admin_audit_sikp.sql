alter type public.user_role add value if not exists 'super_admin';

create or replace function public.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role::text = 'super_admin'
  );
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role::text in ('admin', 'super_admin')
  );
$$;

grant execute on function public.is_admin(), public.is_super_admin()
  to anon, authenticated;

create table public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid,
  actor_role text not null,
  action text not null,
  entity_type text not null,
  entity_id text,
  before jsonb,
  after jsonb,
  created_at timestamptz not null default now()
);

create index audit_logs_created_at_idx on public.audit_logs (created_at desc);
create index audit_logs_entity_idx on public.audit_logs (entity_type, entity_id, created_at desc);
create index audit_logs_action_idx on public.audit_logs (action, created_at desc);

alter table public.audit_logs enable row level security;
revoke all on public.audit_logs from public, anon, authenticated;
grant select on public.audit_logs to authenticated;
grant all on public.audit_logs to service_role;
create policy audit_logs_super_admin_read
  on public.audit_logs for select to authenticated
  using (public.is_super_admin());

create or replace function public.reject_audit_log_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'Audit log bersifat append-only';
end;
$$;

create trigger audit_logs_append_only
  before update or delete on public.audit_logs
  for each row execute function public.reject_audit_log_mutation();

create or replace function public.audit_sensitive_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_role text;
  v_action text;
  v_entity_id text;
  v_before jsonb;
  v_after jsonb;
begin
  if auth.role() = 'service_role' then
    v_actor_role := 'service_role';
  else
    select role::text into v_actor_role
    from public.profiles
    where id = auth.uid();
    v_actor_role := coalesce(v_actor_role, coalesce(auth.role(), 'system'));
  end if;

  if tg_table_name = 'profiles' then
    if old.role is not distinct from new.role then return new; end if;
    v_action := 'user.role_changed';
    v_entity_id := new.id::text;
    v_before := jsonb_build_object('role', old.role::text);
    v_after := jsonb_build_object('role', new.role::text);
  elsif tg_table_name = 'orders' then
    if new.payment_status::text <> 'dibayar'
      or old.payment_status::text = 'dibayar' then return new; end if;
    v_action := 'order.payment_confirmed';
    v_entity_id := new.id::text;
    v_before := jsonb_build_object(
      'payment_status', old.payment_status::text,
      'status', old.status::text
    );
    v_after := jsonb_build_object(
      'payment_status', new.payment_status::text,
      'status', new.status::text,
      'paid_at', new.paid_at
    );
  elsif tg_table_name = 'withdrawal_requests' then
    if old.status is not distinct from new.status then return new; end if;
    v_action := 'withdrawal.processed';
    v_entity_id := new.id::text;
    v_before := jsonb_build_object('status', old.status, 'amount', old.amount, 'umkm_id', old.umkm_id);
    v_after := jsonb_build_object('status', new.status, 'amount', new.amount, 'umkm_id', new.umkm_id);
  elsif tg_table_name = 'vouchers' then
    v_entity_id := coalesce(new.id, old.id)::text;
    if tg_op = 'INSERT' then
      v_action := 'voucher.created';
      v_after := jsonb_build_object(
        'code', new.code, 'discount_type', new.discount_type,
        'discount_value', new.discount_value, 'quota_total', new.quota_total,
        'is_active', new.is_active, 'scope_type', new.scope_type
      );
    elsif tg_op = 'DELETE' then
      v_action := 'voucher.deleted';
      v_before := jsonb_build_object(
        'code', old.code, 'discount_type', old.discount_type,
        'discount_value', old.discount_value, 'quota_total', old.quota_total,
        'is_active', old.is_active, 'scope_type', old.scope_type
      );
    else
      v_action := 'voucher.updated';
      v_before := jsonb_build_object(
        'code', old.code, 'discount_type', old.discount_type,
        'discount_value', old.discount_value, 'quota_total', old.quota_total,
        'is_active', old.is_active, 'scope_type', old.scope_type
      );
      v_after := jsonb_build_object(
        'code', new.code, 'discount_type', new.discount_type,
        'discount_value', new.discount_value, 'quota_total', new.quota_total,
        'is_active', new.is_active, 'scope_type', new.scope_type
      );
      if v_before = v_after then return new; end if;
    end if;
  elsif tg_table_name = 'umkm' then
    if old.is_verified is not distinct from new.is_verified then return new; end if;
    v_action := 'umkm.verification_changed';
    v_entity_id := new.id::text;
    v_before := jsonb_build_object('is_verified', old.is_verified, 'is_active', old.is_active, 'status', old.status);
    v_after := jsonb_build_object('is_verified', new.is_verified, 'is_active', new.is_active, 'status', new.status);
  elsif tg_table_name = 'stock_movements' then
    v_action := 'product.stock_adjusted';
    v_entity_id := new.product_id::text;
    v_after := jsonb_build_object('change', new.change, 'reason', new.reason);
  elsif tg_table_name = 'sikp_export_mapping' then
    if old.columns is not distinct from new.columns then return new; end if;
    v_action := 'sikp.mapping_updated';
    v_entity_id := 'default';
    v_before := jsonb_build_object('columns', old.columns);
    v_after := jsonb_build_object('columns', new.columns);
  else
    raise exception 'Tabel audit tidak didukung: %', tg_table_name;
  end if;

  insert into public.audit_logs (
    actor_id, actor_role, action, entity_type, entity_id, before, after
  ) values (
    auth.uid(), v_actor_role, v_action, tg_table_name, v_entity_id, v_before, v_after
  );

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create trigger profiles_role_audit
  after update of role on public.profiles
  for each row execute function public.audit_sensitive_change();
create trigger orders_payment_audit
  after update of payment_status on public.orders
  for each row execute function public.audit_sensitive_change();
create trigger withdrawal_status_audit
  after update of status on public.withdrawal_requests
  for each row execute function public.audit_sensitive_change();
create trigger vouchers_audit
  after insert or update or delete on public.vouchers
  for each row execute function public.audit_sensitive_change();
create trigger umkm_verification_audit
  after update of is_verified on public.umkm
  for each row execute function public.audit_sensitive_change();
create trigger stock_adjustment_audit
  after insert on public.stock_movements
  for each row execute function public.audit_sensitive_change();

create or replace function public.admin_set_user_role(
  p_user_id uuid,
  p_role public.user_role
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then raise exception 'Akses ditolak'; end if;
  if p_user_id = auth.uid() then raise exception 'Anda tidak dapat mengubah peran sendiri'; end if;
  if p_role::text not in ('customer', 'admin', 'super_admin') then
    raise exception 'Peran tidak valid';
  end if;
  update public.profiles set role = p_role where id = p_user_id;
  if not found then raise exception 'Pengguna tidak ditemukan'; end if;
end;
$$;
revoke all on function public.admin_set_user_role(uuid, public.user_role) from public, anon;
grant execute on function public.admin_set_user_role(uuid, public.user_role) to authenticated;

create table public.sikp_export_mapping (
  id boolean primary key default true check (id),
  columns jsonb not null,
  updated_at timestamptz not null default now(),
  constraint sikp_mapping_columns_array check (jsonb_typeof(columns) = 'array')
);

insert into public.sikp_export_mapping (id, columns) values (
  true,
  '[
    {"header":"PLACEHOLDER_ORDER_REFERENCE","source":"order_no"},
    {"header":"PLACEHOLDER_PAYMENT_DATE","source":"paid_date"},
    {"header":"PLACEHOLDER_ORDER_TOTAL","source":"order_total"},
    {"header":"PLACEHOLDER_UMKM_NAMES","source":"umkm_names"}
  ]'::jsonb
);

create trigger sikp_mapping_audit
  after update on public.sikp_export_mapping
  for each row execute function public.audit_sensitive_change();

alter table public.sikp_export_mapping enable row level security;
revoke all on public.sikp_export_mapping from public, anon, authenticated;
grant select on public.sikp_export_mapping to authenticated;
grant all on public.sikp_export_mapping to service_role;
create policy sikp_mapping_super_admin_read
  on public.sikp_export_mapping for select to authenticated
  using (public.is_super_admin());

create or replace function public.super_admin_update_sikp_mapping(p_columns jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_column jsonb;
  v_seen_headers text[] := '{}';
  v_source text;
  v_header text;
begin
  if not public.is_super_admin() then raise exception 'Akses ditolak'; end if;
  if p_columns is null or jsonb_typeof(p_columns) <> 'array' then
    raise exception 'Pemetaan harus berupa array JSON';
  end if;
  if jsonb_array_length(p_columns) < 1 or jsonb_array_length(p_columns) > 30 then
    raise exception 'Pemetaan harus berupa 1 sampai 30 kolom';
  end if;

  for v_column in select value from jsonb_array_elements(p_columns) loop
    if jsonb_typeof(v_column) <> 'object' then
      raise exception 'Setiap kolom harus berupa objek JSON';
    end if;
    v_header := nullif(trim(v_column->>'header'), '');
    v_source := v_column->>'source';
    if v_header is null or length(v_header) > 120
      or v_source is null
      or (select count(*) from jsonb_object_keys(v_column)) <> 2 then
      raise exception 'Setiap kolom harus memiliki header dan source yang valid';
    end if;
    if v_source not in ('order_no', 'paid_date', 'order_total', 'umkm_names') then
      raise exception 'Sumber data pemetaan tidak diizinkan';
    end if;
    if v_header = any(v_seen_headers) then raise exception 'Header kolom harus unik'; end if;
    v_seen_headers := array_append(v_seen_headers, v_header);
  end loop;

  update public.sikp_export_mapping set columns = p_columns, updated_at = now() where id = true;
end;
$$;

create or replace function public.super_admin_export_sikp(p_from date, p_to date)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_columns jsonb;
  v_column jsonb;
  v_fields text[];
  v_csv text := '';
  v_row record;
  v_value text;
  v_row_count integer := 0;
begin
  if not public.is_super_admin() then raise exception 'Akses ditolak'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then
    raise exception 'Rentang tanggal ekspor tidak valid (maksimal 367 hari)';
  end if;

  select columns into v_columns from public.sikp_export_mapping where id = true;
  if v_columns is null then raise exception 'Pemetaan ekspor belum dikonfigurasi'; end if;

  v_fields := '{}';
  for v_column in select value from jsonb_array_elements(v_columns) loop
    v_fields := array_append(
      v_fields,
      '"' || replace(v_column->>'header', '"', '""') || '"'
    );
  end loop;
  v_csv := array_to_string(v_fields, ',') || E'\r\n';

  for v_row in
    select o.order_no,
      o.paid_at,
      o.total as order_total,
      coalesce(store_names.umkm_names, '') as umkm_names
    from public.orders o
    left join lateral (
      select string_agg(distinct u.name, ' | ' order by u.name) as umkm_names
      from public.order_items oi
      join public.umkm u on u.id = oi.umkm_id
      where oi.order_id = o.id
    ) store_names on true
    where o.payment_status::text = 'dibayar'
      and o.status <> 'dibatalkan'
      and o.paid_at >= (p_from::timestamp at time zone 'Asia/Jakarta')
      and o.paid_at < ((p_to + 1)::timestamp at time zone 'Asia/Jakarta')
    order by o.paid_at, o.order_no
  loop
    v_fields := '{}';
    for v_column in select value from jsonb_array_elements(v_columns) loop
      case v_column->>'source'
        when 'order_no' then v_value := v_row.order_no;
        when 'paid_date' then
          v_value := to_char(v_row.paid_at at time zone 'Asia/Jakarta', 'YYYY-MM-DD HH24:MI:SS');
        when 'order_total' then v_value := v_row.order_total::text;
        when 'umkm_names' then v_value := v_row.umkm_names;
        else raise exception 'Sumber pemetaan ekspor tidak valid';
      end case;
      if coalesce(v_value, '') ~ '^[[:space:]]*[=+@-]' then
        v_value := '''' || v_value;
      end if;
      v_fields := array_append(v_fields, '"' || replace(coalesce(v_value, ''), '"', '""') || '"');
    end loop;
    v_csv := v_csv || array_to_string(v_fields, ',') || E'\r\n';
    v_row_count := v_row_count + 1;
  end loop;

  insert into public.audit_logs (
    actor_id, actor_role, action, entity_type, entity_id, after
  ) values (
    auth.uid(), 'super_admin', 'sikp.exported', 'sikp_export',
    p_from::text || ':' || p_to::text,
    jsonb_build_object('from', p_from, 'to', p_to, 'row_count', v_row_count)
  );
  return v_csv;
end;
$$;

revoke all on function public.super_admin_update_sikp_mapping(jsonb),
  public.super_admin_export_sikp(date, date) from public, anon;
grant execute on function public.super_admin_update_sikp_mapping(jsonb),
  public.super_admin_export_sikp(date, date) to authenticated;

revoke all on function public.reject_audit_log_mutation(),
  public.audit_sensitive_change() from public, anon, authenticated;
