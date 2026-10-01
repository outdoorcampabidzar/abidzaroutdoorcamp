-- AOC V50 MULTI ADMIN + TRAVEL
-- Migration already applied to Supabase project when this package was prepared.
-- This file is a reference/replay migration.

create table if not exists public.travel_packages (
  id uuid primary key default gen_random_uuid(), title text not null, slug text not null unique, description text not null default '', image_url text,
  origin text not null, destination text not null, vehicle_type text, vehicle_name text, capacity integer not null default 0 check (capacity >= 0),
  price numeric(12,2) not null default 0 check (price >= 0), departure_time text, return_time text, pickup_points text, dropoff_points text, facilities text, driver_name text, driver_phone text,
  schedule_days jsonb not null default '[]'::jsonb, status text not null default 'available' check (status in ('available','full','closed','draft')), is_active boolean not null default true, sort_order integer not null default 0,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), created_by uuid references auth.users(id), updated_by uuid references auth.users(id)
);
alter table public.travel_packages enable row level security;
drop policy if exists travel_public_read on public.travel_packages;
create policy travel_public_read on public.travel_packages for select using (is_active=true);

insert into public.role_permissions(role,permission) values ('travel_admin','travel.manage'),('rental_admin','rental.manage'),('sale_admin','sale.manage'),('trip_admin','trip.manage') on conflict do nothing;

-- secure_admin_upsert_travel_package and secure_admin_delete_travel_package are included in the live migration aoc_v50_multi_admin_travel.
-- Catalog item policies and secure_admin_create_rental_item are updated by aoc_v50_catalog_permissions.
