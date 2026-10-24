-- Ownership and review status for UMKM partner applications.
alter table public.umkm
  add column user_id uuid references public.profiles(id) on delete set null,
  add column status text not null default 'active';

alter table public.umkm
  add constraint umkm_status_check check (status in ('pending', 'active'));

create unique index umkm_one_per_user on public.umkm(user_id) where user_id is not null;

create policy umkm_owner_apply on public.umkm for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and status = 'pending'
    and not is_active
    and not is_verified
  );

create or replace function public.get_my_umkm_application()
returns table (
  id uuid,
  name text,
  slug text,
  description text,
  address text,
  phone text,
  status text,
  is_active boolean,
  is_verified boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select u.id, u.name, u.slug, u.description, u.address, u.phone, u.status, u.is_active, u.is_verified
  from public.umkm u
  where u.user_id = (select auth.uid())
  limit 1;
$$;

revoke all on function public.get_my_umkm_application() from public, anon;
grant execute on function public.get_my_umkm_application() to authenticated;

create or replace function public.is_my_umkm(p_umkm_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.umkm u
    where u.id = p_umkm_id
      and u.user_id = (select auth.uid())
  );
$$;

create or replace function public.owns_active_umkm(p_umkm_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.umkm u
    where u.id = p_umkm_id
      and u.user_id = (select auth.uid())
      and u.status = 'active'
      and u.is_active
  );
$$;

revoke all on function public.is_my_umkm(uuid) from public, anon;
revoke all on function public.owns_active_umkm(uuid) from public, anon;
grant execute on function public.is_my_umkm(uuid), public.owns_active_umkm(uuid) to authenticated;

create policy umkm_owner_read on public.umkm for select to authenticated
  using (public.is_my_umkm(id));

create policy products_umkm_owner_read on public.products for select to authenticated
  using (public.owns_active_umkm(umkm_id));

create policy products_umkm_owner_insert on public.products for insert to authenticated
  with check (public.owns_active_umkm(umkm_id));

create policy products_umkm_owner_update on public.products for update to authenticated
  using (public.owns_active_umkm(umkm_id))
  with check (public.owns_active_umkm(umkm_id));

create policy products_umkm_owner_delete on public.products for delete to authenticated
  using (public.owns_active_umkm(umkm_id));

grant select, insert, update on public.umkm to authenticated;
grant select, insert, update, delete on public.products to authenticated;

-- Do not expose profile IDs through the public UMKM catalog.
revoke select on public.umkm from public, anon, authenticated;
grant select (
  id, name, slug, description, region_id, address, phone, logo_url,
  is_verified, is_active, created_at, updated_at, status
) on public.umkm to anon, authenticated;
