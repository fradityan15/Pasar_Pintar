create or replace function public.cancel_order(p_order_id uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v public.orders%rowtype;
  v_cancelled_by_buyer boolean;
begin
  select * into v
  from public.orders
  where id = p_order_id
  for update;

  if not found or (v.user_id <> auth.uid() and not public.is_admin()) then
    raise exception 'Pesanan tidak ditemukan';
  end if;

  v_cancelled_by_buyer := v.user_id = auth.uid() and not public.is_admin();

  if not (
    v.status = 'menunggu_pembayaran'
    or (
      v.status = 'diproses'
      and (
        public.is_admin()
        or (
          v_cancelled_by_buyer
          and exists (
            select 1
            from public.order_items
            where order_id = p_order_id
          )
          and not exists (
            select 1
            from public.order_items
            where order_id = p_order_id
              and seller_shipping_status <> 'menunggu_diproses'
          )
        )
      )
    )
  ) then
    raise exception 'Pesanan tidak dapat dibatalkan pada status ini';
  end if;

  update public.orders
  set status = 'dibatalkan'
  where id = p_order_id;

  perform private.restock_order(p_order_id, 'pesanan dibatalkan');

  insert into public.order_status_logs (order_id, status, changed_by, note)
  values (
    p_order_id,
    'dibatalkan',
    auth.uid(),
    case
      when v_cancelled_by_buyer then 'Pesanan dibatalkan oleh pembeli'
      else coalesce(p_reason, 'Dibatalkan')
    end
  );
end;
$$;
