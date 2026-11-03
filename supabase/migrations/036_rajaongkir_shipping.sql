alter table public.addresses
  add column if not exists rajaongkir_area_id text;
alter table public.umkm
  add column if not exists rajaongkir_origin_area_id text;

create or replace function public.sync_rajaongkir_shipping_areas()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_table_name = 'addresses' then
    new.biteship_area_id := nullif(trim(new.rajaongkir_area_id), '');
  else
    new.biteship_origin_area_id := nullif(trim(new.rajaongkir_origin_area_id), '');
  end if;
  return new;
end;
$$;

drop trigger if exists addresses_sync_rajaongkir_area on public.addresses;
create trigger addresses_sync_rajaongkir_area
  before insert or update on public.addresses
  for each row execute function public.sync_rajaongkir_shipping_areas();

drop trigger if exists umkm_sync_rajaongkir_origin_area on public.umkm;
create trigger umkm_sync_rajaongkir_origin_area
  before insert or update on public.umkm
  for each row execute function public.sync_rajaongkir_shipping_areas();

create or replace function public.get_my_store_settings(p_umkm_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v public.umkm%rowtype;
begin
  if not public.owns_active_umkm(p_umkm_id) then raise exception 'Akses ditolak'; end if;
  select * into v from public.umkm where id = p_umkm_id;
  return jsonb_build_object(
    'id', v.id, 'name', v.name, 'tagline', v.tagline, 'description', v.description,
    'address', v.address, 'region_id', v.region_id, 'logo_url', v.logo_url,
    'banner_url', v.banner_url, 'shipping_providers', v.shipping_providers,
    'bank_name', v.bank_name, 'bank_account_number', v.bank_account_number,
    'bank_account_holder', v.bank_account_holder, 'opening_hours', v.opening_hours,
    'rajaongkir_origin_area_id', v.rajaongkir_origin_area_id
  );
end;
$$;

create or replace function public.save_my_store_settings(p_umkm_id uuid, p_settings jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_providers text[];
  v_allowed_providers constant text[] := array['JNE', 'POS Indonesia', 'TIKI', 'SiCepat', 'J&T Express', 'AnterAja'];
  v_area_id text := nullif(trim(p_settings->>'rajaongkir_origin_area_id'), '');
begin
  if not public.owns_active_umkm(p_umkm_id) then raise exception 'Akses ditolak'; end if;
  if nullif(trim(p_settings->>'name'), '') is null then raise exception 'Nama toko wajib diisi'; end if;
  if v_area_id is null or length(v_area_id) > 80 then
    raise exception 'Wilayah asal RajaOngkir wajib dipilih';
  end if;
  select coalesce(array_agg(p.provider), '{}') into v_providers
  from jsonb_array_elements_text(coalesce(p_settings->'shipping_providers', '[]'::jsonb)) as p(provider);
  if exists (select 1 from unnest(v_providers) p(provider) where p.provider <> all(v_allowed_providers)) then
    raise exception 'Jasa kurir tidak valid';
  end if;
  update public.umkm set
    name = trim(p_settings->>'name'), tagline = nullif(trim(p_settings->>'tagline'), ''),
    description = nullif(trim(p_settings->>'description'), ''),
    address = nullif(trim(p_settings->>'address'), ''),
    region_id = nullif(p_settings->>'region_id', '')::uuid,
    logo_url = nullif(p_settings->>'logo_url', ''), banner_url = nullif(p_settings->>'banner_url', ''),
    shipping_providers = v_providers,
    bank_name = nullif(trim(p_settings->>'bank_name'), ''),
    bank_account_number = nullif(trim(p_settings->>'bank_account_number'), ''),
    bank_account_holder = nullif(trim(p_settings->>'bank_account_holder'), ''),
    opening_hours = coalesce(p_settings->'opening_hours', '{}'::jsonb),
    rajaongkir_origin_area_id = v_area_id
  where id = p_umkm_id;
end;
$$;

revoke all on function public.sync_rajaongkir_shipping_areas() from public, anon, authenticated;
revoke all on function public.get_my_store_settings(uuid), public.save_my_store_settings(uuid, jsonb)
  from public, anon;
grant execute on function public.get_my_store_settings(uuid), public.save_my_store_settings(uuid, jsonb)
  to authenticated;
