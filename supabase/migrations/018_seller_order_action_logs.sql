create or replace function public.seller_process_order(p_order_id uuid, p_umkm_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.owns_active_umkm(p_umkm_id) then
    raise exception 'Akses ditolak';
  end if;

  perform 1
  from public.orders o
  where o.id = p_order_id
    and o.payment_status = 'dibayar'
    and o.status = 'diproses'
  for update;

  if not found then
    raise exception 'Pesanan tidak tersedia untuk diproses';
  end if;

  update public.order_items
  set seller_shipping_status = 'diproses'
  where order_id = p_order_id
    and umkm_id = p_umkm_id
    and seller_shipping_status = 'menunggu_diproses';

  if not found then
    raise exception 'Pesanan tidak tersedia untuk diproses';
  end if;

  insert into public.order_status_logs (order_id, status, changed_by, note)
  values (p_order_id, 'diproses', auth.uid(), 'Pesanan sedang dikemas oleh toko');
end;
$$;

create or replace function public.seller_ship_order(p_order_id uuid, p_umkm_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_all_shipped boolean;
begin
  if not public.owns_active_umkm(p_umkm_id) then
    raise exception 'Akses ditolak';
  end if;

  perform 1
  from public.orders o
  where o.id = p_order_id
    and o.payment_status = 'dibayar'
    and o.status = 'diproses'
  for update;

  if not found then
    raise exception 'Pesanan tidak tersedia untuk dikirim';
  end if;

  update public.order_items
  set seller_shipping_status = 'dikirim'
  where order_id = p_order_id
    and umkm_id = p_umkm_id
    and seller_shipping_status = 'diproses';

  if not found then
    raise exception 'Pesanan tidak tersedia untuk dikirim';
  end if;

  select not exists (
    select 1
    from public.order_items
    where order_id = p_order_id
      and seller_shipping_status <> 'dikirim'
  )
  into v_all_shipped;

  if v_all_shipped then
    update public.orders
    set status = 'dikirim'
    where id = p_order_id
      and status = 'diproses';

    insert into public.order_status_logs (order_id, status, changed_by, note)
    values (p_order_id, 'dikirim', auth.uid(), 'Seluruh mitra telah mengirim barang');
  else
    insert into public.order_status_logs (order_id, status, changed_by, note)
    values (p_order_id, 'diproses', auth.uid(), 'Pesanan telah diserahkan ke kurir oleh toko');
  end if;
end;
$$;

revoke all on function public.seller_process_order(uuid, uuid) from public, anon;
revoke all on function public.seller_ship_order(uuid, uuid) from public, anon;
grant execute on function public.seller_process_order(uuid, uuid) to authenticated;
grant execute on function public.seller_ship_order(uuid, uuid) to authenticated;
