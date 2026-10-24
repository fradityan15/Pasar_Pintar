export const ORDER_STATUS = {
  menunggu_pembayaran: { label: 'Menunggu pembayaran', cls: 'bg-warn-bg text-warn-fg' },
  diproses: { label: 'Diproses', cls: 'bg-info-bg text-info-fg' },
  dikirim: { label: 'Dikirim', cls: 'bg-info-bg text-info-fg' },
  selesai: { label: 'Selesai', cls: 'bg-ok-bg text-ok-fg' },
  dibatalkan: { label: 'Dibatalkan', cls: 'bg-bad-bg text-bad-fg' },
}

export const PAYMENT_METHOD = {
  qris: 'QRIS',
  virtual_account: 'Virtual Account',
  'va-bca': 'Virtual Account BCA',
  'va-mandiri': 'Virtual Account Mandiri',
  'va-bri': 'Virtual Account BRI',
  'va-bni': 'Virtual Account BNI',
  cod: 'Bayar di Tempat (COD)',
}

// Harus sama dengan v_shipping di fungsi create_order (supabase/migrations/003_functions.sql).
export const FLAT_SHIPPING = 15000
