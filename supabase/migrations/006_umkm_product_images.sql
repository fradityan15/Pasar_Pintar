-- Allow active UMKM owners to manage images for their own products.
grant select, insert, update, delete on public.product_images to authenticated;

create policy product_images_umkm_owner_read on public.product_images for select to authenticated
  using (
    exists (
      select 1 from public.products p
      where p.id = product_id
        and public.owns_active_umkm(p.umkm_id)
    )
  );

create policy product_images_umkm_owner_insert on public.product_images for insert to authenticated
  with check (
    exists (
      select 1 from public.products p
      where p.id = product_id
        and public.owns_active_umkm(p.umkm_id)
    )
  );

create policy product_images_umkm_owner_update on public.product_images for update to authenticated
  using (
    exists (
      select 1 from public.products p
      where p.id = product_id
        and public.owns_active_umkm(p.umkm_id)
    )
  )
  with check (
    exists (
      select 1 from public.products p
      where p.id = product_id
        and public.owns_active_umkm(p.umkm_id)
    )
  );

create policy product_images_umkm_owner_delete on public.product_images for delete to authenticated
  using (
    exists (
      select 1 from public.products p
      where p.id = product_id
        and public.owns_active_umkm(p.umkm_id)
    )
  );

create policy "pemilik UMKM unggah foto produk" on storage.objects for insert to authenticated
  with check (
    bucket_id = 'product-images'
    and exists (
      select 1 from public.products p
      where p.id = case
        when split_part(storage.objects.name, '/', 1) ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        then split_part(storage.objects.name, '/', 1)::uuid
        else null
      end
      and public.owns_active_umkm(p.umkm_id)
    )
  );

create policy "pemilik UMKM hapus foto produk" on storage.objects for delete to authenticated
  using (
    bucket_id = 'product-images'
    and exists (
      select 1 from public.products p
      where p.id = case
        when split_part(storage.objects.name, '/', 1) ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        then split_part(storage.objects.name, '/', 1)::uuid
        else null
      end
      and public.owns_active_umkm(p.umkm_id)
    )
  );
