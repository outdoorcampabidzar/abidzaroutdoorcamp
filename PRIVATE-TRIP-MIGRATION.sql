-- AOC: Private Trip category for Travel
-- Existing Travel packages remain in category 'travel'.

alter table public.travel_packages
  add column if not exists category text not null default 'travel';

update public.travel_packages
set category = 'travel'
where category is null or trim(category) = '';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'travel_packages_category_check'
      and conrelid = 'public.travel_packages'::regclass
  ) then
    alter table public.travel_packages
      add constraint travel_packages_category_check
      check (category in ('travel','private_trip'));
  end if;
end $$;

create index if not exists idx_travel_packages_category
  on public.travel_packages(category, is_active, sort_order);

create or replace function public.secure_admin_upsert_travel_package(
  p_id uuid default null,
  p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_row public.travel_packages%rowtype;
  v_category text := case when coalesce(p_payload->>'category','travel') = 'private_trip' then 'private_trip' else 'travel' end;
begin
  if auth.uid() is null then raise exception 'Silakan login terlebih dahulu'; end if;
  if not public.aoc_is_admin_account() then raise exception 'Akun ini bukan akun admin'; end if;
  if not public.has_permission('travel.manage') and not public.has_permission('*') then raise exception 'Izin Travel diperlukan'; end if;
  if not exists (select 1 from public.admin_security_verifications where user_id=auth.uid() and verified_until>now()) then
    raise exception 'Verifikasi PIN Admin diperlukan sebelum mengubah Travel';
  end if;
  if nullif(trim(coalesce(p_payload->>'title','')),'') is null then raise exception 'Nama paket Travel wajib diisi'; end if;
  if nullif(trim(coalesce(p_payload->>'origin','')),'') is null then raise exception 'Kota asal wajib diisi'; end if;
  if nullif(trim(coalesce(p_payload->>'destination','')),'') is null then raise exception 'Kota tujuan wajib diisi'; end if;
  if nullif(trim(coalesce(p_payload->>'slug','')),'') is null then raise exception 'Slug Travel wajib diisi'; end if;

  if p_id is null then
    insert into public.travel_packages(
      title,slug,description,image_url,origin,destination,vehicle_type,vehicle_name,
      capacity,price,departure_time,return_time,pickup_points,dropoff_points,
      facilities,driver_name,driver_phone,schedule_days,category,status,is_active,sort_order,created_by,updated_by
    ) values(
      trim(p_payload->>'title'),trim(p_payload->>'slug'),coalesce(p_payload->>'description',''),
      nullif(trim(coalesce(p_payload->>'image_url','')),''),
      trim(p_payload->>'origin'),trim(p_payload->>'destination'),
      nullif(trim(coalesce(p_payload->>'vehicle_type','')),''),
      nullif(trim(coalesce(p_payload->>'vehicle_name','')),''),
      greatest(coalesce((p_payload->>'capacity')::integer,0),0),
      greatest(coalesce((p_payload->>'price')::numeric,0),0),
      nullif(trim(coalesce(p_payload->>'departure_time','')),''),
      nullif(trim(coalesce(p_payload->>'return_time','')),''),
      nullif(trim(coalesce(p_payload->>'pickup_points','')),''),
      nullif(trim(coalesce(p_payload->>'dropoff_points','')),''),
      nullif(trim(coalesce(p_payload->>'facilities','')),''),
      nullif(trim(coalesce(p_payload->>'driver_name','')),''),
      nullif(trim(coalesce(p_payload->>'driver_phone','')),''),
      case when jsonb_typeof(p_payload->'schedule_days')='array' then p_payload->'schedule_days' else '[]'::jsonb end,
      v_category,
      case when coalesce(p_payload->>'status','available') in ('available','full','closed','draft') then p_payload->>'status' else 'available' end,
      coalesce((p_payload->>'is_active')::boolean,true),
      coalesce((p_payload->>'sort_order')::integer,0),auth.uid(),auth.uid()
    ) returning * into v_row;
  else
    update public.travel_packages set
      title=trim(p_payload->>'title'),slug=trim(p_payload->>'slug'),
      description=coalesce(p_payload->>'description',''),
      image_url=nullif(trim(coalesce(p_payload->>'image_url','')),''),
      origin=trim(p_payload->>'origin'),destination=trim(p_payload->>'destination'),
      vehicle_type=nullif(trim(coalesce(p_payload->>'vehicle_type','')),''),
      vehicle_name=nullif(trim(coalesce(p_payload->>'vehicle_name','')),''),
      capacity=greatest(coalesce((p_payload->>'capacity')::integer,0),0),
      price=greatest(coalesce((p_payload->>'price')::numeric,0),0),
      departure_time=nullif(trim(coalesce(p_payload->>'departure_time','')),''),
      return_time=nullif(trim(coalesce(p_payload->>'return_time','')),''),
      pickup_points=nullif(trim(coalesce(p_payload->>'pickup_points','')),''),
      dropoff_points=nullif(trim(coalesce(p_payload->>'dropoff_points','')),''),
      facilities=nullif(trim(coalesce(p_payload->>'facilities','')),''),
      driver_name=nullif(trim(coalesce(p_payload->>'driver_name','')),''),
      driver_phone=nullif(trim(coalesce(p_payload->>'driver_phone','')),''),
      schedule_days=case when jsonb_typeof(p_payload->'schedule_days')='array' then p_payload->'schedule_days' else '[]'::jsonb end,
      category=v_category,
      status=case when coalesce(p_payload->>'status','available') in ('available','full','closed','draft') then p_payload->>'status' else 'available' end,
      is_active=coalesce((p_payload->>'is_active')::boolean,true),
      sort_order=coalesce((p_payload->>'sort_order')::integer,0),
      updated_at=now(),updated_by=auth.uid()
    where id=p_id returning * into v_row;
    if not found then raise exception 'Paket Travel tidak ditemukan'; end if;
  end if;
  return to_jsonb(v_row);
exception when unique_violation then raise exception 'Slug Travel sudah digunakan';
end;
$function$;

comment on column public.travel_packages.category is 'Travel category: travel or private_trip. Private Trip can only be created/managed through Admin Travel.';
