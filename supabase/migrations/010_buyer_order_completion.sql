create or replace function public.confirm_order_received(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v public.orders%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Anda harus masuk untuk mengonfirmasi pesanan';
  end if;

  select * into v
  from public.orders
  where id = p_order_id
  for update;

  if not found or v.user_id <> auth.uid() then
    raise exception 'Pesanan tidak ditemukan';
  end if;

  if v.status <> 'dikirim' then
    raise exception 'Pesanan hanya dapat dikonfirmasi setelah dikirim';
  end if;

  update public.orders
  set status = 'selesai'
  where id = p_order_id;

  insert into public.order_status_logs (order_id, status, changed_by, note)
  values (p_order_id, 'selesai', auth.uid(), 'Penerimaan barang dikonfirmasi oleh pembeli');
end;
$$;

revoke all on function public.confirm_order_received(uuid) from public, anon;
grant execute on function public.confirm_order_received(uuid) to authenticated;
