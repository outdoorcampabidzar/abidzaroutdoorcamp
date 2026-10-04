-- AOC MEMBER ID CARD / DATA ANGGOTA
-- Fitur terpisah dari membership_cards.

create table if not exists public.member_id_cards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  member_code text not null unique,
  full_name text not null,
  photo_url text,
  "position" text,
  department text,
  join_date date,
  status text not null default 'active' check (status in ('active','inactive','suspended')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_member_id_cards_code on public.member_id_cards(member_code);
create index if not exists idx_member_id_cards_status on public.member_id_cards(status);

alter table public.member_id_cards enable row level security;

-- Tidak memberi SELECT umum. Halaman member membaca melalui RPC publik yang aman.
drop policy if exists "member id cards admin all" on public.member_id_cards;
create policy "member id cards admin all" on public.member_id_cards
for all to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Bucket foto anggota.
insert into storage.buckets (id, name, public)
values ('member-photos', 'member-photos', true)
on conflict (id) do update set public = true;

drop policy if exists "member photos admin insert" on storage.objects;
create policy "member photos admin insert" on storage.objects
for insert to authenticated
with check (bucket_id = 'member-photos' and public.is_admin());

drop policy if exists "member photos admin update" on storage.objects;
create policy "member photos admin update" on storage.objects
for update to authenticated
using (bucket_id = 'member-photos' and public.is_admin())
with check (bucket_id = 'member-photos' and public.is_admin());

drop policy if exists "member photos admin delete" on storage.objects;
create policy "member photos admin delete" on storage.objects
for delete to authenticated
using (bucket_id = 'member-photos' and public.is_admin());

create or replace function public.aoc_generate_member_code()
returns text
language plpgsql
as $$
declare
  v_code text;
begin
  loop
    v_code := 'AOC-MBR-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 8));
    exit when not exists (select 1 from public.member_id_cards where member_code = v_code);
  end loop;
  return v_code;
end;
$$;

create or replace function public.secure_admin_upsert_member_id_card(
  p_id uuid,
  p_payload jsonb
)
returns public.member_id_cards
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.member_id_cards;
  v_user_id uuid;
  v_code text;
begin
  if not public.is_admin() then
    raise exception 'Akses ditolak. Hanya administrator yang dapat mengelola Data Anggota.' using errcode = '42501';
  end if;

  v_user_id := nullif(trim(coalesce(p_payload->>'user_id','')), '')::uuid;
  if v_user_id is null then
    raise exception 'user_id wajib diisi';
  end if;

  if p_id is null then
    v_code := nullif(trim(coalesce(p_payload->>'member_code','')), '');
    if v_code is null then v_code := public.aoc_generate_member_code(); end if;
    insert into public.member_id_cards(user_id, member_code, full_name, photo_url, position, department, join_date, status, notes)
    values (
      v_user_id,
      v_code,
      coalesce(nullif(trim(coalesce(p_payload->>'full_name','')), ''), 'Anggota'),
      nullif(trim(coalesce(p_payload->>'photo_url','')), ''),
      nullif(trim(coalesce(p_payload->>'position','')), ''),
      nullif(trim(coalesce(p_payload->>'department','')), ''),
      nullif(p_payload->>'join_date','')::date,
      coalesce(nullif(trim(coalesce(p_payload->>'status','')), ''), 'active'),
      nullif(trim(coalesce(p_payload->>'notes','')), '')
    ) returning * into v_row;
  else
    update public.member_id_cards
    set user_id = v_user_id,
        full_name = coalesce(nullif(trim(coalesce(p_payload->>'full_name','')), ''), full_name),
        photo_url = case when p_payload ? 'photo_url' then nullif(trim(coalesce(p_payload->>'photo_url','')), '') else photo_url end,
        position = nullif(trim(coalesce(p_payload->>'position','')), ''),
        department = nullif(trim(coalesce(p_payload->>'department','')), ''),
        join_date = nullif(p_payload->>'join_date','')::date,
        status = coalesce(nullif(trim(coalesce(p_payload->>'status','')), ''), 'active'),
        notes = nullif(trim(coalesce(p_payload->>'notes','')), ''),
        updated_at = now()
    where id = p_id
    returning * into v_row;
    if v_row.id is null then raise exception 'Data anggota tidak ditemukan'; end if;
  end if;
  return v_row;
end;
$$;

grant execute on function public.secure_admin_upsert_member_id_card(uuid,jsonb) to authenticated;

drop function if exists public.get_public_member_id_card(text);

create or replace function public.get_public_member_id_card(p_member_code text)
returns table (
  id uuid,
  user_id uuid,
  member_code text,
  full_name text,
  photo_url text,
  "position" text,
  department text,
  join_date date,
  status text,
  notes text
)
language sql
security definer
set search_path = public
as $$
  select m.id, m.user_id, m.member_code, m.full_name, m.photo_url, m.position as "position", m.department, m.join_date, m.status, m.notes
  from public.member_id_cards m
  where upper(m.member_code) = upper(trim(p_member_code))
    and m.status <> 'suspended'
  limit 1;
$$;

grant execute on function public.get_public_member_id_card(text) to anon, authenticated;

-- Admin dapat melihat semua data melalui tabel/RLS; customer publik hanya lewat RPC.

-- Hak akses Data Anggota untuk akun administrator.
insert into public.role_permissions(role, permission)
select r.role_name, 'members.manage'
from (values ('admin'),('super_admin'),('superadmin'),('order_admin'),('catalog_admin'),('finance_admin'),('warehouse_staff'),('rental_admin'),('sale_admin'),('trip_admin'),('travel_admin')) as r(role_name)
on conflict do nothing;


-- V81: Hapus Data Anggota / ID Card (admin only).
drop function if exists public.secure_admin_delete_member_id_card(uuid);
create or replace function public.secure_admin_delete_member_id_card(
  p_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted boolean := false;
begin
  if not public.is_admin() then
    raise exception 'Akses ditolak. Hanya administrator yang dapat menghapus Data Anggota.' using errcode = '42501';
  end if;

  delete from public.member_id_cards
  where id = p_id;

  v_deleted := found;
  if not v_deleted then
    raise exception 'Data Anggota tidak ditemukan.';
  end if;

  return true;
end;
$$;

grant execute on function public.secure_admin_delete_member_id_card(uuid) to authenticated;
