create or replace function public.seller_ship_order(p_order_id uuid, p_umkm_id uuid)
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
    raise exception 'Pesanan tidak tersedia untuk dikirim';
  end if;

  if not exists (
    select 1
    from public.order_items oi
    where oi.order_id = p_order_id
      and oi.umkm_id = p_umkm_id
      and oi.seller_shipping_status = 'diproses'
  ) then
    raise exception 'Pesanan tidak tersedia untuk dikirim';
  end if;

  update public.order_items
  set seller_shipping_status = 'dikirim'
  where order_id = p_order_id
    and umkm_id = p_umkm_id
    and seller_shipping_status = 'diproses';

  if not exists (
    select 1
    from public.order_items
    where order_id = p_order_id
      and seller_shipping_status <> 'dikirim'
  ) then
    update public.orders
    set status = 'dikirim'
    where id = p_order_id
      and status = 'diproses';

    if found then
      insert into public.order_status_logs (order_id, status, changed_by, note)
      values (p_order_id, 'dikirim', auth.uid(), 'Seluruh mitra telah mengirim barang');
    end if;
  end if;
end;
$$;

revoke all on function public.seller_ship_order(uuid, uuid) from public, anon;
grant execute on function public.seller_ship_order(uuid, uuid) to authenticated;
