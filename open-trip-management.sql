-- Jalankan sesudah catalog-management.sql dan sebelum rental-calendar.sql.
create table if not exists public.trip_details (
  item_id uuid primary key references public.items(id) on delete cascade,
  departure_at timestamptz,
  return_at timestamptz,
  meeting_point text,
  meeting_time text,
  itinerary text,
  included_facilities text,
  excluded_facilities text,
  difficulty text not null default 'moderate' check (difficulty in ('easy','moderate','hard','extreme')),
  min_age integer check (min_age is null or min_age >= 0),
  max_age integer check (max_age is null or max_age >= min_age),
  required_equipment text,
  min_participants integer not null default 1 check (min_participants > 0),
  registration_deadline timestamptz,
  status text not null default 'draft' check (status in ('draft','open','full','running','completed','cancelled')),
  travel_information text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.trip_participants (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  item_id uuid not null references public.items(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  seat_number integer not null check (seat_number > 0),
  full_name text not null,
  phone text not null,
  age integer not null check (age > 0),
  identity_last4 text,
  emergency_contact_name text not null,
  emergency_contact_phone text not null,
  notes text,
  status text not null default 'registered' check (status in ('registered','confirmed','cancelled','attended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (item_id, order_id, seat_number)
);

create index if not exists trip_participants_item_idx on public.trip_participants(item_id, status);
create index if not exists trip_participants_order_idx on public.trip_participants(order_id);

alter table public.trip_details enable row level security;
alter table public.trip_participants enable row level security;

drop policy if exists "trip details public read" on public.trip_details;
create policy "trip details public read" on public.trip_details for select using (true);
drop policy if exists "trip details admin write" on public.trip_details;
create policy "trip details admin write" on public.trip_details for all using (public.is_admin()) with check (public.is_admin());
drop policy if exists "participants own read" on public.trip_participants;
create policy "participants own read" on public.trip_participants for select using (auth.uid() = user_id or public.is_admin());
drop policy if exists "participants admin write" on public.trip_participants;
create policy "participants admin write" on public.trip_participants for all using (public.is_admin()) with check (public.is_admin());

insert into public.trip_details (item_id, departure_at, status)
select id, case when trip_date is null then null else trip_date::timestamp at time zone 'Asia/Jakarta' end,
       case when is_active then 'open' else 'draft' end
from public.items where type = 'trip'
on conflict (item_id) do nothing;

create or replace function public.admin_update_trip_participant_status(p_participant_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Akses ditolak'; end if;
  if p_status not in ('registered','confirmed','cancelled','attended') then raise exception 'Status tidak valid'; end if;
  update public.trip_participants set status = p_status, updated_at = now() where id = p_participant_id;
end; $$;
revoke all on function public.admin_update_trip_participant_status(uuid,text) from public;
grant execute on function public.admin_update_trip_participant_status(uuid,text) to authenticated;
