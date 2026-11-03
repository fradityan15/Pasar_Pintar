drop policy if exists umkm_read on public.umkm;
create policy umkm_read on public.umkm
  for select to anon, authenticated
  using (is_active and is_verified and status = 'active');

drop policy if exists products_read on public.products;
create policy products_read on public.products
  for select to anon, authenticated
  using (
    is_active
    and exists (
      select 1
      from public.umkm u
      where u.id = products.umkm_id
        and u.is_active
        and u.is_verified
        and u.status = 'active'
    )
  );

drop policy if exists product_images_read on public.product_images;
create policy product_images_read on public.product_images
  for select to anon, authenticated
  using (
    exists (
      select 1
      from public.products p
      join public.umkm u on u.id = p.umkm_id
      where p.id = product_images.product_id
        and p.is_active
        and u.is_active
        and u.is_verified
        and u.status = 'active'
    )
  );

create or replace function public.admin_approve_umkm(p_umkm_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Akses ditolak';
  end if;

  update public.umkm
  set status = 'active',
      is_active = true,
      is_verified = true
  where id = p_umkm_id
    and status = 'pending';

  if not found then
    raise exception 'Pendaftaran UMKM tidak ditemukan atau sudah diproses';
  end if;
end;
$$;

revoke all on function public.admin_approve_umkm(uuid) from public, anon;
grant execute on function public.admin_approve_umkm(uuid) to authenticated;
