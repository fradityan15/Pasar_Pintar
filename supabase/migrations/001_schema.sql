-- PasarPintar · 001 · Skema database
-- Jalankan di Supabase: SQL Editor → New query → tempel → Run.

create extension if not exists pgcrypto;
create schema if not exists private;

create type public.user_role as enum ('admin', 'customer');
create type public.order_status as enum ('menunggu_pembayaran', 'diproses', 'dikirim', 'selesai', 'dibatalkan');
create type public.payment_status as enum ('belum_dibayar', 'dibayar', 'kedaluwarsa');

create or replace function public.set_updated_at() returns trigger
language plpgsql as $$
begin new.updated_at := now(); return new; end $$;

-- ───────── Pengguna ─────────
create table public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  full_name   text not null default '',
  phone       text,
  role        public.user_role not null default 'customer',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table public.addresses (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles(id) on delete cascade,
  label           text not null default 'Rumah',
  recipient_name  text not null,
  phone           text not null,
  province        text not null,
  city            text not null,
  street          text not null,
  postal_code     text,
  is_default      boolean not null default false,
  created_at      timestamptz not null default now()
);
create unique index addresses_one_default on public.addresses(user_id) where is_default;

-- Profil otomatis dibuat saat pengguna mendaftar. Peran selalu 'customer'.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', ''));
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ───────── Katalog ─────────
create table public.regions (
  id        uuid primary key default gen_random_uuid(),
  name      text not null,
  province  text not null,
  unique (name, province)
);

create table public.categories (
  id         uuid primary key default gen_random_uuid(),
  parent_id  uuid references public.categories(id) on delete restrict,
  name       text not null,
  slug       text not null unique,
  is_active  boolean not null default true
);

create table public.umkm (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  slug         text not null unique,
  description  text,
  region_id    uuid references public.regions(id) on delete set null,
  address      text,
  phone        text,
  logo_url     text,
  is_verified  boolean not null default false,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table public.products (
  id           uuid primary key default gen_random_uuid(),
  umkm_id      uuid not null references public.umkm(id) on delete restrict,
  category_id  uuid references public.categories(id) on delete set null,
  name         text not null,
  slug         text not null unique,
  description  text,
  price        numeric(12,0) not null check (price >= 0),
  stock        integer not null default 0 check (stock >= 0),
  weight_gram  integer not null default 0 check (weight_gram >= 0),
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table public.product_images (
  id          uuid primary key default gen_random_uuid(),
  product_id  uuid not null references public.products(id) on delete cascade,
  url         text not null,
  sort_order  integer not null default 0
);

-- ───────── Keranjang & pesanan ─────────
create table public.cart_items (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  product_id  uuid not null references public.products(id) on delete cascade,
  quantity    integer not null check (quantity > 0),
  unique (user_id, product_id)
);

create sequence public.order_no_seq;

create table public.orders (
  id                  uuid primary key default gen_random_uuid(),
  order_no            text not null unique default (
    'PP-' || to_char(now() at time zone 'Asia/Jakarta', 'YYMMDD') || '-' ||
    lpad(nextval('public.order_no_seq')::text, 4, '0')),
  user_id             uuid not null references public.profiles(id) on delete restrict,
  status              public.order_status not null default 'menunggu_pembayaran',
  payment_status      public.payment_status not null default 'belum_dibayar',
  payment_method      text not null check (payment_method in ('qris', 'virtual_account')),
  subtotal            numeric(12,0) not null,
  shipping_cost       numeric(12,0) not null default 0,
  total               numeric(12,0) not null,
  shipping_address    jsonb not null,           -- salinan alamat saat checkout
  payment_expires_at  timestamptz,
  paid_at             timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create table public.order_items (
  id            uuid primary key default gen_random_uuid(),
  order_id      uuid not null references public.orders(id) on delete cascade,
  product_id    uuid references public.products(id) on delete set null,
  umkm_id       uuid references public.umkm(id) on delete set null,
  product_name  text not null,                  -- salinan nama & harga saat dibeli
  unit_price    numeric(12,0) not null,
  quantity      integer not null check (quantity > 0)
);

create table public.order_status_logs (
  id          bigint generated always as identity primary key,
  order_id    uuid not null references public.orders(id) on delete cascade,
  status      public.order_status not null,
  changed_by  uuid references public.profiles(id) on delete set null,
  note        text,
  created_at  timestamptz not null default now()
);

create table public.stock_movements (
  id          bigint generated always as identity primary key,
  product_id  uuid not null references public.products(id) on delete cascade,
  change      integer not null,
  reason      text not null,
  order_id    uuid references public.orders(id) on delete set null,
  created_by  uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now()
);

-- ───────── Indeks & trigger ─────────
create index on public.products (category_id);
create index on public.products (umkm_id);
create index on public.products (is_active);
create index on public.umkm (region_id);
create index on public.categories (parent_id);
create index on public.orders (user_id, created_at desc);
create index on public.orders (status);
create index on public.order_items (order_id);
create index on public.order_status_logs (order_id);
create index on public.stock_movements (product_id);
create index on public.cart_items (user_id);

create trigger trg_profiles_updated before update on public.profiles for each row execute function public.set_updated_at();
create trigger trg_umkm_updated     before update on public.umkm     for each row execute function public.set_updated_at();
create trigger trg_products_updated before update on public.products for each row execute function public.set_updated_at();
create trigger trg_orders_updated   before update on public.orders   for each row execute function public.set_updated_at();
