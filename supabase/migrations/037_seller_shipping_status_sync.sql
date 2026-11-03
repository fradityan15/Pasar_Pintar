create or replace function public.seller_ship_order(
  p_order_id uuid,
  p_umkm_id uuid,
  p_courier text,
  p_tracking_number text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_payment_category text;
  v_all_shipped boolean;
begin
  if not public.owns_active_umkm(p_umkm_id) then
    raise exception 'Akses ditolak';
  end if;
  if p_courier is null or p_courier !~ '^[a-z0-9_-]{2,30}$'
    or p_tracking_number is null or p_tracking_number !~ '^[A-Za-z0-9-]{6,40}$' then
    raise exception 'Kurir atau nomor resi tidak valid';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;
  if not found or v_order.status not in ('menunggu_diproses', 'diproses') then
    raise exception 'Pesanan tidak tersedia untuk dikirim';
  end if;

  select coalesce(pm.category, case when v_order.payment_method = 'cod' then 'cod' end)
  into v_payment_category
  from (select 1) singleton
  left join public.payment_methods pm on pm.id = v_order.payment_method_id;
  if v_order.payment_status::text <> 'dibayar' and v_payment_category <> 'cod' then
    raise exception 'Pembayaran pesanan belum dikonfirmasi';
  end if;

  if not exists (
    select 1 from public.order_items oi
    where oi.order_id = p_order_id
      and oi.umkm_id = p_umkm_id
      and oi.seller_shipping_status = 'diproses'
      and oi.courier = p_courier
  ) then
    raise exception 'Kurir tidak sesuai tarif yang dipilih atau pesanan tidak siap dikirim';
  end if;

  if v_order.status = 'menunggu_diproses' then
    update public.orders set status = 'diproses' where id = p_order_id;
  end if;

  update public.order_items
  set seller_shipping_status = 'dikirim',
      tracking_number = upper(p_tracking_number)
  where order_id = p_order_id
    and umkm_id = p_umkm_id
    and seller_shipping_status = 'diproses'
    and courier = p_courier;
  if not found then
    raise exception 'Pesanan tidak tersedia untuk dikirim';
  end if;

  select not exists (
    select 1 from public.order_items
    where order_id = p_order_id
      and seller_shipping_status <> 'dikirim'
  ) into v_all_shipped;

  if v_all_shipped then
    update public.orders
    set status = 'dikirim',
        tracking_number = case
          when (select count(distinct tracking_number)
            from public.order_items where order_id = p_order_id) = 1
          then upper(p_tracking_number)
          else null
        end
    where id = p_order_id and status = 'diproses';
    insert into public.order_status_logs (order_id, status, changed_by, note)
    values (p_order_id, 'dikirim', auth.uid(), 'Seluruh mitra telah mengirim barang');
  else
    insert into public.order_status_logs (order_id, status, changed_by, note)
    values (p_order_id, 'diproses', auth.uid(), 'Toko mengirim barang dengan kurir ' || p_courier);
  end if;

  insert into public.shipment_events (
    order_id, courier, tracking_number, event_key, status, description, occurred_at
  )
  values (
    p_order_id,
    p_courier,
    upper(p_tracking_number),
    'seller-shipped-' || p_umkm_id::text,
    'dikirim',
    case when upper(p_tracking_number) like 'DEMO-%'
      then 'Pengiriman demo ditandai dikirim (simulasi presentasi)'
      else 'Paket telah diserahkan kepada kurir'
    end,
    now()
  )
  on conflict (order_id, event_key) do nothing;
end;
$$;

revoke all on function public.seller_ship_order(uuid, uuid, text, text) from public, anon;
grant execute on function public.seller_ship_order(uuid, uuid, text, text) to authenticated;
