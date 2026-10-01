-- Private Trip mengikuti struktur Open Trip
alter table public.travel_packages
  add column if not exists meeting_point text,
  add column if not exists meeting_time text,
  add column if not exists itinerary text,
  add column if not exists included_facilities text,
  add column if not exists excluded_facilities text,
  add column if not exists required_equipment text,
  add column if not exists difficulty text default 'moderate',
  add column if not exists min_participants integer default 1,
  add column if not exists min_age integer,
  add column if not exists max_age integer,
  add column if not exists travel_information text;

-- Data Private Trip lama tidak lagi memakai field transportasi/akomodasi.
update public.travel_packages
set vehicle_type=null, vehicle_name=null, driver_name=null, driver_phone=null, schedule_days='[]'::jsonb
where category='private_trip';

-- secure_admin_upsert_travel_package pada database AOC juga sudah diperbarui
-- agar menerima field Open Trip di atas untuk category='private_trip'.
