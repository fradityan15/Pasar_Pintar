alter type public.order_status
  add value if not exists 'menunggu_diproses' after 'menunggu_pembayaran';
