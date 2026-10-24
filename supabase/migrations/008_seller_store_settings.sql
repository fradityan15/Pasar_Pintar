alter table public.umkm
  add column tagline text,
  add column banner_url text,
  add column shipping_providers text[] not null default '{}',
  add column bank_name text,
  add column bank_account_number text,
  add column bank_account_holder text,
  add column opening_hours jsonb not null default '{}'::jsonb;

grant select (tagline, banner_url, shipping_providers) on public.umkm to anon, authenticated;

insert into storage.buckets (id, name, public)
values ('seller-assets', 'seller-assets', true)
on conflict (id) do nothing;

create policy "aset toko dibaca publik" on storage.objects for select
  using (bucket_id = 'seller-assets');

create policy "pemilik UMKM unggah aset toko" on storage.objects for insert to authenticated
  with check (
    bucket_id = 'seller-assets'
    and public.owns_active_umkm(
      case
        when split_part(storage.objects.name, '/', 1) ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        then split_part(storage.objects.name, '/', 1)::uuid
        else null
      end
    )
  );

create policy "pemilik UMKM hapus aset toko" on storage.objects for delete to authenticated
  using (
    bucket_id = 'seller-assets'
    and public.owns_active_umkm(
      case
        when split_part(storage.objects.name, '/', 1) ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        then split_part(storage.objects.name, '/', 1)::uuid
        else null
      end
    )
  );

create or replace function public.get_my_store_settings(p_umkm_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v public.umkm%rowtype;
begin
  if not public.owns_active_umkm(p_umkm_id) then
    raise exception 'Akses ditolak';
  end if;

  select * into v from public.umkm where id = p_umkm_id;
  return jsonb_build_object(
    'id', v.id,
    'name', v.name,
    'tagline', v.tagline,
    'description', v.description,
    'address', v.address,
    'region_id', v.region_id,
    'logo_url', v.logo_url,
    'banner_url', v.banner_url,
    'shipping_providers', v.shipping_providers,
    'bank_name', v.bank_name,
    'bank_account_number', v.bank_account_number,
    'bank_account_holder', v.bank_account_holder,
    'opening_hours', v.opening_hours
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
begin
  if not public.owns_active_umkm(p_umkm_id) then
    raise exception 'Akses ditolak';
  end if;

  if nullif(trim(p_settings->>'name'), '') is null then
    raise exception 'Nama toko wajib diisi';
  end if;

  select coalesce(array_agg(p.provider), '{}')
  into v_providers
  from jsonb_array_elements_text(coalesce(p_settings->'shipping_providers', '[]'::jsonb)) as p(provider);

  if exists (select 1 from unnest(v_providers) as p(provider) where p.provider <> all(v_allowed_providers)) then
    raise exception 'Jasa kurir tidak valid';
  end if;

  update public.umkm
  set name = trim(p_settings->>'name'),
      tagline = nullif(trim(p_settings->>'tagline'), ''),
      description = nullif(trim(p_settings->>'description'), ''),
      address = nullif(trim(p_settings->>'address'), ''),
      region_id = nullif(p_settings->>'region_id', '')::uuid,
      logo_url = nullif(p_settings->>'logo_url', ''),
      banner_url = nullif(p_settings->>'banner_url', ''),
      shipping_providers = v_providers,
      bank_name = nullif(trim(p_settings->>'bank_name'), ''),
      bank_account_number = nullif(trim(p_settings->>'bank_account_number'), ''),
      bank_account_holder = nullif(trim(p_settings->>'bank_account_holder'), ''),
      opening_hours = coalesce(p_settings->'opening_hours', '{}'::jsonb)
  where id = p_umkm_id;
end;
$$;

revoke all on function public.get_my_store_settings(uuid) from public, anon;
revoke all on function public.save_my_store_settings(uuid, jsonb) from public, anon;
grant execute on function public.get_my_store_settings(uuid) to authenticated;
grant execute on function public.save_my_store_settings(uuid, jsonb) to authenticated;
