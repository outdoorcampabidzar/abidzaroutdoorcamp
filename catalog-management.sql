-- Pengelolaan katalog lanjutan AbidzarOutdoorcamp
-- Jalankan sekali melalui Supabase SQL Editor.

create table if not exists public.item_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.items
  add column if not exists category_id uuid references public.item_categories(id) on delete set null,
  add column if not exists deposit numeric(14,2) not null default 0,
  add column if not exists is_featured boolean not null default false,
  add column if not exists sort_order integer not null default 0,
  add column if not exists archived_at timestamptz;

create table if not exists public.item_images (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id) on delete cascade,
  image_url text not null,
  alt_text text,
  is_primary boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create unique index if not exists item_images_one_primary_idx
  on public.item_images(item_id) where is_primary;

create table if not exists public.item_variants (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id) on delete cascade,
  name text not null,
  capacity text,
  price_adjustment numeric(14,2) not null default 0,
  stock integer not null default 0 check (stock >= 0),
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.inventory_units (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id) on delete restrict,
  variant_id uuid references public.item_variants(id) on delete set null,
  inventory_number text not null unique,
  condition text not null default 'good'
    check (condition in ('new', 'good', 'fair', 'damaged')),
  status text not null default 'available'
    check (status in ('available', 'rented', 'damaged', 'maintenance', 'retired')),
  notes text,
  purchased_at date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.item_price_tiers (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id) on delete cascade,
  label text not null,
  duration_days integer not null check (duration_days > 0),
  price numeric(14,2) not null check (price >= 0),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  unique(item_id, duration_days)
);
alter table public.item_price_tiers
  add column if not exists variant_id uuid references public.item_variants(id) on delete cascade;
alter table public.item_price_tiers
  drop constraint if exists item_price_tiers_item_id_duration_days_key;
create unique index if not exists item_price_tiers_variant_duration_idx
  on public.item_price_tiers(item_id,variant_id,duration_days)
  where variant_id is not null;
create unique index if not exists item_price_tiers_default_duration_idx
  on public.item_price_tiers(item_id,duration_days)
  where variant_id is null;

create or replace view public.item_inventory_summary
with (security_invoker = true) as
select
  i.id as item_id,
  count(u.id) filter (where u.status = 'available')::integer as available,
  count(u.id) filter (where u.status = 'rented')::integer as rented,
  count(u.id) filter (where u.status = 'damaged')::integer as damaged,
  count(u.id) filter (where u.status = 'maintenance')::integer as maintenance,
  count(u.id) filter (where u.status = 'retired')::integer as retired,
  count(u.id)::integer as total_units
from public.items i
left join public.inventory_units u on u.item_id = i.id
group by i.id;

create index if not exists items_catalog_sort_idx
  on public.items(type, is_featured desc, sort_order, created_at desc)
  where archived_at is null;
create index if not exists inventory_units_item_status_idx
  on public.inventory_units(item_id, status);
create index if not exists item_images_item_sort_idx
  on public.item_images(item_id, sort_order);

alter table public.item_categories enable row level security;
alter table public.item_images enable row level security;
alter table public.item_variants enable row level security;
alter table public.inventory_units enable row level security;
alter table public.item_price_tiers enable row level security;

drop policy if exists "categories public read" on public.item_categories;
create policy "categories public read" on public.item_categories for select
using (is_active or public.is_admin());
drop policy if exists "categories admin write" on public.item_categories;
create policy "categories admin write" on public.item_categories for all
to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "item images public read" on public.item_images;
create policy "item images public read" on public.item_images for select using (true);
drop policy if exists "item images admin write" on public.item_images;
create policy "item images admin write" on public.item_images for all
to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "item variants public read" on public.item_variants;
create policy "item variants public read" on public.item_variants for select
using (is_active or public.is_admin());
drop policy if exists "item variants admin write" on public.item_variants;
create policy "item variants admin write" on public.item_variants for all
to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "inventory admin all" on public.inventory_units;
create policy "inventory admin all" on public.inventory_units for all
to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "price tiers public read" on public.item_price_tiers;
create policy "price tiers public read" on public.item_price_tiers for select using (true);
drop policy if exists "price tiers admin write" on public.item_price_tiers;
create policy "price tiers admin write" on public.item_price_tiers for all
to authenticated using (public.is_admin()) with check (public.is_admin());

grant select on public.item_categories, public.item_images, public.item_variants,
  public.item_price_tiers, public.item_inventory_summary to anon, authenticated;
grant select, insert, update, delete on public.item_categories, public.item_images,
  public.item_variants, public.inventory_units, public.item_price_tiers to authenticated;

-- Pastikan gambar utama lama ikut masuk ke galeri tanpa menggandakan data.
insert into public.item_images(item_id, image_url, alt_text, is_primary, sort_order)
select i.id, i.image_url, i.title, true, 0
from public.items i
where nullif(i.image_url, '') is not null
  and not exists (select 1 from public.item_images x where x.item_id = i.id);

-- Bucket publik untuk upload foto katalog dari admin panel.
insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('catalog', 'catalog', true, 8388608, array['image/jpeg','image/png','image/webp','image/gif'])
on conflict (id) do update set public = true;

drop policy if exists "catalog images public read" on storage.objects;
create policy "catalog images public read" on storage.objects for select
using (bucket_id = 'catalog');
drop policy if exists "catalog images admin insert" on storage.objects;
create policy "catalog images admin insert" on storage.objects for insert
to authenticated with check (bucket_id = 'catalog' and public.is_admin());
drop policy if exists "catalog images admin update" on storage.objects;
create policy "catalog images admin update" on storage.objects for update
to authenticated using (bucket_id = 'catalog' and public.is_admin());
drop policy if exists "catalog images admin delete" on storage.objects;
create policy "catalog images admin delete" on storage.objects for delete
to authenticated using (bucket_id = 'catalog' and public.is_admin());
