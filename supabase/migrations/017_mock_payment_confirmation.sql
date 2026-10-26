create or replace function public.simulate_payment_confirmation(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_note text;
begin
  if auth.uid() is null then
    raise exception 'Silakan login terlebih dahulu';
  end if;

  select *
  into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found or v_order.user_id <> auth.uid() then
    raise exception 'Pesanan tidak ditemukan';
  end if;

  if v_order.status <> 'menunggu_pembayaran'
    or v_order.payment_status not in ('pending', 'belum_dibayar') then
    raise exception 'Pesanan ini tidak sedang menunggu pembayaran';
  end if;

  if v_order.payment_expires_at is not null and v_order.payment_expires_at <= now() then
    raise exception 'Batas waktu pembayaran telah berakhir';
  end if;

  v_note := case
    when v_order.payment_method = 'cod' then 'Simulasi konfirmasi pembayaran COD'
    else 'Simulasi pembayaran berhasil'
  end;

  update public.orders
  set payment_status = 'dibayar',
      status = 'diproses'
  where id = p_order_id;

  insert into public.order_status_logs (order_id, status, changed_by, note)
  values (p_order_id, 'diproses', auth.uid(), v_note);
end;
$$;

revoke all on function public.simulate_payment_confirmation(uuid) from public, anon;
grant execute on function public.simulate_payment_confirmation(uuid) to authenticated;
