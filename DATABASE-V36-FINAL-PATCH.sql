-- ================================================================
-- ABIDZAR OUTDOORCAMP V36 - FINAL UPDATE PATCH
--
-- Mempertahankan konsep yang sudah ada:
-- REGISTER -> BUAT HOME PIN -> IDENTITY -> BERANDA -> HOME PIN
-- Home PIN: bcrypt, 6 digit, 5 salah = lock 30 menit, tanpa sesi unlock.
-- Transaction PIN tetap hanya untuk transaksi/checkout.
-- Admin panel tidak meminta Transaction PIN.
-- Admin permission tetap per akun.
-- Reset omzet tetap melalui RPC aman.
-- Pengumuman beranda tetap aktif dan tidak menghilang saat kosong/error.
-- Galeri: semua akun terdaftar yang login dapat upload; publik dapat melihat.
--
-- Jalankan SEKALI di Supabase SQL Editor pada database AOC yang sudah ada.
-- ================================================================

begin;

-- ---------- 1. HOME SECURITY PIN: WAJIB SETIAP MASUK BERANDA ----------
create extension if not exists pgcrypto with schema extensions;
create schema if not exists private;

create table if not exists private.aoc_home_security_pins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  pin_hash text not null,
  failed_attempts integer not null default 0,
  locked_until timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists private.aoc_home_security_pin_sessions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  verified_until timestamptz not null,
  created_at timestamptz not null default now()
);

alter table private.aoc_home_security_pins enable row level security;
alter table private.aoc_home_security_pin_sessions enable row level security;
revoke all on private.aoc_home_security_pins from public, anon, authenticated;
revoke all on private.aoc_home_security_pin_sessions from public, anon, authenticated;

create or replace function public.aoc_validate_home_pin(p_pin text)
returns void language plpgsql immutable
set search_path=public,pg_temp as $$
declare v_pin text:=trim(coalesce(p_pin,''));
begin
  if v_pin !~ '^\d{6}$' then raise exception 'PIN keamanan beranda harus tepat 6 digit.'; end if;
  if v_pin in ('000000','111111','222222','333333','444444','555555','666666','777777','888888','999999','123456','654321','123123','321321','121212','112233','223344','334455','445566','556677','667788','778899','987654') then
    raise exception 'PIN terlalu mudah ditebak. Gunakan kombinasi 6 digit yang lebih kuat.';
  end if;
end; $$;

create or replace function public.has_home_security_pin()
returns boolean language sql security definer stable
set search_path=public,private,pg_temp as $$
  select exists(select 1 from private.aoc_home_security_pins where user_id=auth.uid());
$$;

create or replace function public.set_home_security_pin(p_pin text)
returns jsonb language plpgsql security definer
set search_path=public,private,pg_temp as $$
declare v_user_id uuid:=auth.uid(); v_pin text:=trim(coalesce(p_pin,''));
begin
  if v_user_id is null then raise exception 'Silakan login terlebih dahulu.'; end if;
  perform public.aoc_validate_home_pin(v_pin);
  insert into private.aoc_home_security_pins(user_id,pin_hash,failed_attempts,locked_until,updated_at)
  values(v_user_id,extensions.crypt(v_pin,extensions.gen_salt('bf',12)),0,null,now())
  on conflict(user_id) do update set pin_hash=excluded.pin_hash,failed_attempts=0,locked_until=null,updated_at=now();
  delete from private.aoc_home_security_pin_sessions where user_id=v_user_id;
  return jsonb_build_object('success',true,'message','PIN keamanan beranda berhasil disimpan.');
end; $$;

create or replace function public.verify_home_security_pin(p_pin text)
returns jsonb language plpgsql security definer
set search_path=public,private,pg_temp as $$
declare
  v_user_id uuid:=auth.uid(); v_pin text:=trim(coalesce(p_pin,''));
  v_row private.aoc_home_security_pins%rowtype; v_attempts integer; v_locked_until timestamptz;
begin
  if v_user_id is null then raise exception 'Silakan login terlebih dahulu.'; end if;
  if v_pin !~ '^\d{6}$' then return jsonb_build_object('success',false,'code','PIN_INVALID_FORMAT','message','PIN harus tepat 6 digit.'); end if;
  select * into v_row from private.aoc_home_security_pins where user_id=v_user_id for update;
  if not found then return jsonb_build_object('success',false,'code','PIN_NOT_SET','message','PIN keamanan beranda belum dibuat.'); end if;
  if v_row.locked_until is not null and v_row.locked_until>now() then
    return jsonb_build_object('success',false,'code','PIN_LOCKED','message','PIN keamanan beranda terkunci sementara karena terlalu banyak percobaan salah.','locked_until',v_row.locked_until);
  end if;
  if extensions.crypt(v_pin,v_row.pin_hash)<>v_row.pin_hash then
    update private.aoc_home_security_pins set failed_attempts=failed_attempts+1,locked_until=case when failed_attempts+1>=5 then now()+interval '30 minutes' else null end,updated_at=now() where user_id=v_user_id;
    select failed_attempts,locked_until into v_attempts,v_locked_until from private.aoc_home_security_pins where user_id=v_user_id;
    if v_locked_until is not null and v_locked_until>now() then return jsonb_build_object('success',false,'code','PIN_LOCKED','message','5 kali PIN salah. PIN dikunci selama 30 menit.','locked_until',v_locked_until); end if;
    return jsonb_build_object('success',false,'code','PIN_WRONG','message','PIN keamanan beranda salah.','remaining_attempts',greatest(0,5-v_attempts));
  end if;
  update private.aoc_home_security_pins set failed_attempts=0,locked_until=null,updated_at=now() where user_id=v_user_id;
  delete from private.aoc_home_security_pin_sessions where user_id=v_user_id;
  return jsonb_build_object('success',true,'message','PIN keamanan beranda benar.');
end; $$;

create or replace function public.get_home_security_pin_session()
returns jsonb language sql security definer stable
set search_path=public,private,pg_temp as $$
  select jsonb_build_object('verified',false,'verified_until',null);
$$;

revoke all on function public.aoc_validate_home_pin(text) from public,anon,authenticated;
revoke all on function public.has_home_security_pin() from public,anon,authenticated;
revoke all on function public.set_home_security_pin(text) from public,anon,authenticated;
revoke all on function public.verify_home_security_pin(text) from public,anon,authenticated;
revoke all on function public.get_home_security_pin_session() from public,anon,authenticated;
grant execute on function public.aoc_validate_home_pin(text) to authenticated;
grant execute on function public.has_home_security_pin() to authenticated;
grant execute on function public.set_home_security_pin(text) to authenticated;
grant execute on function public.verify_home_security_pin(text) to authenticated;
grant execute on function public.get_home_security_pin_session() to authenticated;

-- ---------- 2. ONBOARDING IDENTITY CHECK ----------
create or replace function public.has_complete_identity()
returns boolean language sql security definer stable set search_path=public,pg_temp as $$
  select exists(
    select 1 from public.profiles p
    where p.id=auth.uid()
      and length(trim(coalesce(p.full_name,'')))>=3
      and length(trim(coalesce(p.phone,'')))>=10
      and length(trim(coalesce(p.city,'')))>=2
      and length(trim(coalesce(p.address,'')))>=8
  );
$$;
revoke all on function public.has_complete_identity() from public,anon,authenticated;
grant execute on function public.has_complete_identity() to authenticated;

-- ---------- 3. PENGUMUMAN BERANDA ----------
create table if not exists public.site_announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  content text not null,
  category text not null default 'info' check (category in ('info','promo','warning','event','new')),
  image_url text,
  action_label text,
  action_url text,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint announcement_dates check (ends_at is null or ends_at > starts_at)
);
alter table public.site_announcements enable row level security;
drop policy if exists announcements_public_read on public.site_announcements;
create policy announcements_public_read on public.site_announcements for select using (is_active=true and starts_at<=now() and (ends_at is null or ends_at>now()));
drop policy if exists announcements_admin_read on public.site_announcements;
create policy announcements_admin_read on public.site_announcements for select using (public.has_permission('site.announcements.manage') or public.has_permission('*'));
drop policy if exists announcements_admin_insert on public.site_announcements;
create policy announcements_admin_insert on public.site_announcements for insert with check (public.has_permission('site.announcements.manage') or public.has_permission('*'));
drop policy if exists announcements_admin_update on public.site_announcements;
create policy announcements_admin_update on public.site_announcements for update using (public.has_permission('site.announcements.manage') or public.has_permission('*')) with check (public.has_permission('site.announcements.manage') or public.has_permission('*'));
drop policy if exists announcements_admin_delete on public.site_announcements;
create policy announcements_admin_delete on public.site_announcements for delete using (public.has_permission('site.announcements.manage') or public.has_permission('*'));
create index if not exists site_announcements_active_idx on public.site_announcements(is_active,starts_at,ends_at,sort_order);

-- ---------- 4. COMMUNITY GALLERY ----------
create table if not exists public.community_gallery (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  file_name text not null,
  file_path text not null unique,
  file_url text not null,
  mime_type text not null,
  file_size bigint not null default 0,
  caption text,
  created_at timestamptz not null default now()
);
create index if not exists community_gallery_created_idx on public.community_gallery(created_at desc);
create index if not exists community_gallery_user_idx on public.community_gallery(user_id,created_at desc);
alter table public.community_gallery enable row level security;
drop policy if exists "gallery public read" on public.community_gallery;
create policy "gallery public read" on public.community_gallery for select using (true);
drop policy if exists "gallery authenticated insert" on public.community_gallery;
create policy "gallery authenticated insert" on public.community_gallery for insert to authenticated with check (auth.uid()=user_id);
drop policy if exists "gallery owner delete" on public.community_gallery;
create policy "gallery owner delete" on public.community_gallery for delete to authenticated using (auth.uid()=user_id);
revoke all on table public.community_gallery from anon;
grant select on table public.community_gallery to anon;
grant select,insert,delete on table public.community_gallery to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('community-gallery','community-gallery',true,15728640,array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm','application/pdf'])
on conflict(id) do update set public=true,file_size_limit=15728640,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists "gallery storage public read" on storage.objects;
create policy "gallery storage public read" on storage.objects for select using (bucket_id='community-gallery');
drop policy if exists "gallery storage authenticated upload" on storage.objects;
create policy "gallery storage authenticated upload" on storage.objects for insert to authenticated with check (bucket_id='community-gallery' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "gallery storage owner delete" on storage.objects;
create policy "gallery storage owner delete" on storage.objects for delete to authenticated using (bucket_id='community-gallery' and (storage.foldername(name))[1]=auth.uid()::text);

commit;
notify pgrst,'reload schema';
