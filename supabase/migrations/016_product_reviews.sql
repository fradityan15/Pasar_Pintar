-- Ulasan hanya dapat dibuat oleh pembeli yang memiliki pesanan selesai atas produk.
create table public.product_reviews (
  id          uuid primary key default gen_random_uuid(),
  product_id  uuid not null references public.products(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  rating      smallint not null check (rating between 1 and 5),
  comment     text check (comment is null or char_length(comment) <= 2000),
  created_at  timestamptz not null default now(),
  unique (product_id, user_id)
);

create index product_reviews_product_created_at_idx
  on public.product_reviews (product_id, created_at desc);

alter table public.product_reviews enable row level security;

create policy product_reviews_public_read
  on public.product_reviews for select to anon, authenticated
  using (true);

create policy product_reviews_verified_purchase_insert
  on public.product_reviews for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1
      from public.order_items oi
      join public.orders o on o.id = oi.order_id
      where oi.product_id = product_reviews.product_id
        and o.user_id = (select auth.uid())
        and o.status = 'selesai'
    )
  );

revoke all on public.product_reviews from public, anon, authenticated;
grant select (id, product_id, rating, comment, created_at)
  on public.product_reviews to anon, authenticated;
grant insert (product_id, user_id, rating, comment)
  on public.product_reviews to authenticated;

create or replace function public.get_my_reviewed_product_ids()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select product_id
  from public.product_reviews
  where user_id = (select auth.uid());
$$;

revoke all on function public.get_my_reviewed_product_ids() from public, anon;
grant execute on function public.get_my_reviewed_product_ids() to authenticated;
