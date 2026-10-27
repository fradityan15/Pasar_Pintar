-- COD lifecycle, trusted manual payment verification, and complete report aggregation.
update public.orders
set paid_at = coalesce(updated_at, created_at)
where payment_status = 'dibayar'
  and paid_at is null;

create or replace function public.top_products_report(
  p_from date,
  p_to date,
  p_limit integer default 5
)
returns table (
  product_name text,
  quantity bigint,
  revenue numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Akses ditolak';
  end if;
  if p_from is null or p_to is null or p_to < p_from then
    raise exception 'Rentang tanggal tidak valid';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception 'Batas hasil harus antara 1 dan 100';
  end if;

  return query
  select
    oi.product_name,
    sum(oi.quantity)::bigint,
    sum(oi.unit_price * oi.quantity)::numeric
  from public.order_items oi
  join public.orders o on o.id = oi.order_id
  where o.payment_status = 'dibayar'
    and o.status <> 'dibatalkan'
    and o.created_at >= (p_from::timestamp at time zone 'Asia/Jakarta')
    and o.created_at < ((p_to + 1)::timestamp at time zone 'Asia/Jakarta')
  group by oi.product_name
  order by sum(oi.quantity) desc, sum(oi.unit_price * oi.quantity) desc, oi.product_name
  limit p_limit;
end;
$$;

revoke all on function public.top_products_report(date, date, integer) from public, anon;
grant execute on function public.top_products_report(date, date, integer) to authenticated;

drop function if exists public.simulate_payment_confirmation(uuid);

create or replace function public.admin_confirm_order_payment(
  p_order_id uuid,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_payment_category text;
begin
  if not public.is_admin() then
    raise exception 'Akses ditolak';
  end if;

  select *
  into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Pesanan tidak ditemukan';
  end if;

  if v_order.status <> 'menunggu_pembayaran'
    or v_order.payment_status not in ('pending', 'belum_dibayar') then
    raise exception 'Pesanan ini tidak sedang menunggu pembayaran';
  end if;

  if v_order.payment_expires_at is not null and v_order.payment_expires_at <= now() then
    raise exception 'Batas waktu pembayaran telah berakhir';
  end if;

  select category
  into v_payment_category
  from public.payment_methods
  where id = v_order.payment_method_id;

  v_payment_category := coalesce(
    v_payment_category,
    case
      when v_order.payment_method = 'cod' then 'cod'
      when v_order.payment_method = 'qris' then 'qris'
      when v_order.payment_method in ('virtual_account', 'va-bca', 'va-mandiri', 'va-bri', 'va-bni', 'bank_transfer') then 'bank_transfer'
    end
  );
  if coalesce(v_payment_category, '') not in ('qris', 'va', 'bank_transfer') then
    raise exception 'Metode pembayaran ini tidak dapat diverifikasi sebagai transfer';
  end if;

  update public.orders
  set payment_status = 'dibayar',
      status = 'diproses',
      paid_at = coalesce(paid_at, now())
  where id = p_order_id;

  insert into public.order_status_logs (order_id, status, changed_by, note)
  values (
    p_order_id,
    'diproses',
    auth.uid(),
    coalesce(nullif(trim(p_note), ''), 'Pembayaran transfer diverifikasi oleh admin')
  );
end;
$$;

revoke all on function public.admin_confirm_order_payment(uuid, text) from public, anon;
grant execute on function public.admin_confirm_order_payment(uuid, text) to authenticated;

create or replace function public.seller_process_order(p_order_id uuid, p_umkm_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_payment_category text;
begin
  if not public.owns_active_umkm(p_umkm_id) then
    raise exception 'Akses ditolak';
  end if;

  select *
  into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Pesanan tidak tersedia untuk diproses';
  end if;

  select category
  into v_payment_category
  from public.payment_methods
  where id = v_order.payment_method_id;

  v_payment_category := coalesce(
    v_payment_category,
    case when v_order.payment_method = 'cod' then 'cod' end
  );

  if not (
    (v_order.status = 'diproses' and v_order.payment_status = 'dibayar')
    or (v_order.status in ('menunggu_pembayaran', 'diproses') and v_payment_category = 'cod')
  ) then
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

  if v_order.status = 'menunggu_pembayaran' then
    update public.orders
    set status = 'diproses'
    where id = p_order_id;
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
  v_order public.orders%rowtype;
  v_payment_category text;
begin
  if not public.owns_active_umkm(p_umkm_id) then
    raise exception 'Akses ditolak';
  end if;

  select *
  into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found or v_order.status <> 'diproses' then
    raise exception 'Pesanan tidak tersedia untuk dikirim';
  end if;

  select category
  into v_payment_category
  from public.payment_methods
  where id = v_order.payment_method_id;

  v_payment_category := coalesce(
    v_payment_category,
    case when v_order.payment_method = 'cod' then 'cod' end
  );

  if v_order.payment_status <> 'dibayar' and coalesce(v_payment_category, '') <> 'cod' then
    raise exception 'Pembayaran pesanan belum dikonfirmasi';
  end if;

  update public.order_items
  set seller_shipping_status = 'dikirim'
  where order_id = p_order_id
    and umkm_id = p_umkm_id
    and seller_shipping_status = 'diproses';

  if not found then
    raise exception 'Pesanan tidak tersedia untuk dikirim';
  end if;

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

    insert into public.order_status_logs (order_id, status, changed_by, note)
    values (p_order_id, 'dikirim', auth.uid(), 'Seluruh mitra telah mengirim barang');
  else
    insert into public.order_status_logs (order_id, status, changed_by, note)
    values (p_order_id, 'diproses', auth.uid(), 'Pesanan telah diserahkan ke kurir oleh toko');
  end if;
end;
$$;

create or replace function public.confirm_order_received(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_payment_category text;
begin
  if auth.uid() is null then
    raise exception 'Anda harus masuk untuk mengonfirmasi pesanan';
  end if;

  select *
  into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found or v_order.user_id <> auth.uid() then
    raise exception 'Pesanan tidak ditemukan';
  end if;

  if v_order.status <> 'dikirim' then
    raise exception 'Pesanan hanya dapat dikonfirmasi setelah dikirim';
  end if;

  select category
  into v_payment_category
  from public.payment_methods
  where id = v_order.payment_method_id;

  v_payment_category := coalesce(
    v_payment_category,
    case when v_order.payment_method = 'cod' then 'cod' end
  );

  update public.orders
  set status = 'selesai',
      payment_status = case
        when v_payment_category = 'cod' then 'dibayar'
        else payment_status
      end,
      paid_at = case
        when v_payment_category = 'cod' then coalesce(paid_at, now())
        else paid_at
      end
  where id = p_order_id;

  insert into public.order_status_logs (order_id, status, changed_by, note)
  values (
    p_order_id,
    'selesai',
    auth.uid(),
    case
      when v_payment_category = 'cod' then 'Pesanan COD diterima dan pembayaran dikonfirmasi oleh pembeli'
      else 'Penerimaan barang dikonfirmasi oleh pembeli'
    end
  );
end;
$$;

revoke all on function public.seller_process_order(uuid, uuid) from public, anon;
revoke all on function public.seller_ship_order(uuid, uuid) from public, anon;
revoke all on function public.confirm_order_received(uuid) from public, anon;
grant execute on function public.seller_process_order(uuid, uuid) to authenticated;
grant execute on function public.seller_ship_order(uuid, uuid) to authenticated;
grant execute on function public.confirm_order_received(uuid) to authenticated;
