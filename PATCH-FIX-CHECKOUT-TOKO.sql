-- ============================================================
-- AOC FIX: TOKO CHECKOUT + LOCATION ORDER
-- Jalankan SEKALI di Supabase SQL Editor setelah backup database.
-- Aman dijalankan ulang (idempotent).
-- ============================================================

begin;

create table if not exists public.aoc_locations (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  address text,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

-- Toko yang sudah ada dipertahankan. Hanya isi jika belum ada.
insert into public.aoc_locations(code, name, sort_order)
values ('TOKO1', 'Toko 1', 1), ('TOKO2', 'Toko 2', 2)
on conflict (code) do update
set name = excluded.name,
    sort_order = excluded.sort_order;

alter table public.profiles
  add column if not exists location_id uuid
  references public.aoc_locations(id) on delete set null;

alter table public.orders
  add column if not exists location_id uuid
  references public.aoc_locations(id) on delete set null;

alter table public.aoc_locations enable row level security;

drop policy if exists "aoc locations public read" on public.aoc_locations;
create policy "aoc locations public read"
on public.aoc_locations
for select
using (is_active or public.is_admin());

grant select on public.aoc_locations to anon, authenticated;

-- Akun lama yang belum punya toko diarahkan ke Toko 1.
update public.profiles
set location_id = (
  select id from public.aoc_locations
  where code = 'TOKO1' and is_active
  limit 1
)
where location_id is null;

create or replace function public.aoc_current_location_id()
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_location_id uuid;
begin
  if auth.uid() is not null then
    select p.location_id
      into v_location_id
      from public.profiles p
     where p.id = auth.uid();
  end if;

  return coalesce(
    v_location_id,
    (select l.id
       from public.aoc_locations l
      where l.code = 'TOKO1'
        and l.is_active
      order by l.sort_order
      limit 1),
    (select l.id
       from public.aoc_locations l
      where l.is_active
      order by l.sort_order
      limit 1)
  );
end;
$$;

create or replace function public.aoc_set_current_location(p_location_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Login diperlukan';
  end if;

  if not exists (
    select 1
      from public.aoc_locations
     where id = p_location_id
       and is_active = true
  ) then
    raise exception 'Lokasi tidak valid';
  end if;

  update public.profiles
     set location_id = p_location_id
   where id = auth.uid();

  if not found then
    raise exception 'Profil pengguna tidak ditemukan';
  end if;
end;
$$;

grant execute on function public.aoc_current_location_id() to anon, authenticated;
grant execute on function public.aoc_set_current_location(uuid) to authenticated;

-- INI YANG MEMASTIKAN ORDER SELALU MEMBAWA TOKO YANG DIPILIH.
-- create_order tidak perlu diubah: trigger mengisi location_id saat INSERT.
create or replace function public.aoc_orders_set_location()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.location_id is null then
    new.location_id := public.aoc_current_location_id();
  end if;

  if new.location_id is null then
    raise exception 'Lokasi toko belum tersedia';
  end if;

  return new;
end;
$$;

drop trigger if exists aoc_orders_set_location_trigger on public.orders;

create trigger aoc_orders_set_location_trigger
before insert on public.orders
for each row
execute function public.aoc_orders_set_location();

notify pgrst, 'reload schema';

commit;
