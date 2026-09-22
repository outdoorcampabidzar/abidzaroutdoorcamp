-- AOC Ultimate: Member 360 + QR scanner + asset QR + points + scan audit
-- Jalankan SETELAH access-security.sql, customer-review-notification.sql,
-- PATCH-MEMBERSHIP-CARD.sql, catalog-management.sql, dan MULTI-LOKASI-STOCK.sql.

create table if not exists public.aoc_member_points (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  points integer not null default 0 check (points >= 0),
  updated_at timestamptz not null default now(),
  unique(user_id)
);
alter table public.aoc_member_points enable row level security;
drop policy if exists aoc_member_points_read on public.aoc_member_points;
create policy aoc_member_points_read on public.aoc_member_points for select using (user_id=auth.uid() or public.has_permission('customers.view') or public.has_permission('*'));
drop policy if exists aoc_member_points_write on public.aoc_member_points;
create policy aoc_member_points_write on public.aoc_member_points for all using (public.has_permission('customers.manage') or public.has_permission('*')) with check (public.has_permission('customers.manage') or public.has_permission('*'));


create table if not exists public.aoc_item_qr_assets (
  id uuid primary key default gen_random_uuid(),
  asset_code text not null unique,
  item_id uuid not null references public.items(id) on delete restrict,
  variant_id uuid references public.item_variants(id) on delete set null,
  location_id uuid references public.aoc_locations(id) on delete set null,
  status text not null default 'available' check (status in ('available','rented','damaged','maintenance','retired')),
  condition text not null default 'good' check (condition in ('new','good','fair','damaged')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists aoc_item_qr_assets_item_idx on public.aoc_item_qr_assets(item_id,variant_id);
create index if not exists aoc_item_qr_assets_location_idx on public.aoc_item_qr_assets(location_id);
alter table public.aoc_item_qr_assets enable row level security;
drop policy if exists aoc_item_qr_assets_read on public.aoc_item_qr_assets;
create policy aoc_item_qr_assets_read on public.aoc_item_qr_assets for select using (true);
drop policy if exists aoc_item_qr_assets_write on public.aoc_item_qr_assets;
create policy aoc_item_qr_assets_write on public.aoc_item_qr_assets for all using (public.has_permission('warehouse.manage') or public.has_permission('catalog.manage') or public.has_permission('*')) with check (public.has_permission('warehouse.manage') or public.has_permission('catalog.manage') or public.has_permission('*'));

create table if not exists public.aoc_scan_audit (
  id bigint generated always as identity primary key,
  admin_user_id uuid references auth.users(id) on delete set null,
  scan_type text not null check (scan_type in ('member','item','order')),
  scan_value text not null,
  result_id text,
  created_at timestamptz not null default now()
);
alter table public.aoc_scan_audit enable row level security;
drop policy if exists aoc_scan_audit_read on public.aoc_scan_audit;
create policy aoc_scan_audit_read on public.aoc_scan_audit for select using (public.has_permission('*'));
drop policy if exists aoc_scan_audit_insert on public.aoc_scan_audit;
create policy aoc_scan_audit_insert on public.aoc_scan_audit for insert with check (public.is_admin());

create or replace function public.aoc_secure_member_lookup(p_code text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_card public.membership_cards; v_profile public.profiles; v_points integer; v_history jsonb; v_total numeric;
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  select * into v_card from public.membership_cards where upper(card_number)=upper(trim(p_code)) or user_id=case when trim(p_code) ~* '^[0-9a-f-]{36}$' then trim(p_code)::uuid else null end limit 1;
  if v_card.id is null then raise exception 'Member tidak ditemukan'; end if;
  select * into v_profile from public.profiles where id=v_card.user_id;
  select coalesce(points,0) into v_points from public.aoc_member_points where user_id=v_card.user_id;
  select coalesce(sum(o.total) filter(where o.status <> 'cancelled'),0) into v_total from public.orders o where o.user_id=v_card.user_id;
  select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'order_number',o.order_number,'status',o.status,'payment_status',o.payment_status,'total',o.total,'created_at',o.created_at,'rental_start',o.rental_start,'rental_end',o.rental_end) order by o.created_at desc), '[]'::jsonb)
    into v_history from public.orders o where o.user_id=v_card.user_id;
  insert into public.aoc_scan_audit(admin_user_id,scan_type,scan_value,result_id) values(auth.uid(),'member',trim(p_code),v_card.user_id::text);
  return jsonb_build_object('member',jsonb_build_object('user_id',v_card.user_id,'full_name',v_profile.full_name,'phone',v_profile.phone,'city',v_profile.city,'email',(select email::text from auth.users where id=v_card.user_id),'is_verified',v_profile.is_verified,'is_blocked',v_profile.is_blocked),'card',to_jsonb(v_card),'points',coalesce(v_points,0),'total_spent',v_total,'history',v_history);
end $$;
revoke all on function public.aoc_secure_member_lookup(text) from public;
grant execute on function public.aoc_secure_member_lookup(text) to authenticated;

create or replace function public.aoc_secure_item_qr_lookup(p_code text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_asset public.aoc_item_qr_assets; v_item public.items; v_variant public.item_variants; v_location public.aoc_locations;
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  select * into v_asset from public.aoc_item_qr_assets where upper(asset_code)=upper(trim(p_code));
  if v_asset.id is null then raise exception 'QR barang tidak ditemukan'; end if;
  select * into v_item from public.items where id=v_asset.item_id;
  if v_asset.variant_id is not null then select * into v_variant from public.item_variants where id=v_asset.variant_id; end if;
  if v_asset.location_id is not null then select * into v_location from public.aoc_locations where id=v_asset.location_id; end if;
  insert into public.aoc_scan_audit(admin_user_id,scan_type,scan_value,result_id) values(auth.uid(),'item',trim(p_code),v_asset.id::text);
  return jsonb_build_object('asset',to_jsonb(v_asset),'item',jsonb_build_object('id',v_item.id,'title',v_item.title,'type',v_item.type),'variant',case when v_variant.id is null then null else jsonb_build_object('id',v_variant.id,'name',v_variant.name,'capacity',v_variant.capacity) end,'location',case when v_location.id is null then null else jsonb_build_object('id',v_location.id,'name',v_location.name,'code',v_location.code) end);
end $$;
revoke all on function public.aoc_secure_item_qr_lookup(text) from public;
grant execute on function public.aoc_secure_item_qr_lookup(text) to authenticated;

create or replace function public.aoc_secure_set_asset_status(p_asset_id uuid,p_status text,p_condition text default null,p_notes text default null)
returns public.aoc_item_qr_assets language plpgsql security definer set search_path=public as $$
declare v public.aoc_item_qr_assets;
begin
  if not (public.has_permission('warehouse.manage') or public.has_permission('*')) then raise exception 'Izin gudang diperlukan'; end if;
  if p_status not in ('available','rented','damaged','maintenance','retired') then raise exception 'Status barang tidak valid'; end if;
  if p_condition is not null and p_condition not in ('new','good','fair','damaged') then raise exception 'Kondisi barang tidak valid'; end if;
  update public.aoc_item_qr_assets set status=p_status,condition=coalesce(p_condition,condition),notes=coalesce(p_notes,notes),updated_at=now() where id=p_asset_id returning * into v;
  if v.id is null then raise exception 'Asset tidak ditemukan'; end if;
  return v;
end $$;
revoke all on function public.aoc_secure_set_asset_status(uuid,text,text,text) from public;
grant execute on function public.aoc_secure_set_asset_status(uuid,text,text,text) to authenticated;

create or replace function public.aoc_secure_add_member_points(p_user_id uuid,p_points integer)
returns integer language plpgsql security definer set search_path=public as $$
declare v integer;
begin
  if not (public.has_permission('customers.manage') or public.has_permission('*')) then raise exception 'Izin pelanggan diperlukan'; end if;
  if p_points=0 then return 0; end if;
  insert into public.aoc_member_points(user_id,points) values(p_user_id,greatest(p_points,0)) on conflict(user_id) do update set points=greatest(0,aoc_member_points.points+p_points),updated_at=now() returning points into v;
  return v;
end $$;
revoke all on function public.aoc_secure_add_member_points(uuid,integer) from public;
grant execute on function public.aoc_secure_add_member_points(uuid,integer) to authenticated;
