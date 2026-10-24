insert into public.payment_methods (
  name,
  category,
  account_number,
  account_name,
  is_active
)
select
  seed.name,
  seed.category,
  seed.account_number,
  seed.account_name,
  true
from (
  values
    (
      'Bayar di Tempat (COD)',
      'cod',
      null::text,
      null::text
    ),
    (
      'Bank BCA',
      'bank_transfer',
      '8077-1234-5678',
      'PT Pasar Pintar Indonesia'
    ),
    (
      'Bank Mandiri',
      'bank_transfer',
      '1370-000-111-222',
      'PT Pasar Pintar Indonesia'
    )
) as seed(name, category, account_number, account_name)
where not exists (
  select 1
  from public.payment_methods as existing
  where existing.name = seed.name
    and existing.category = seed.category
);
