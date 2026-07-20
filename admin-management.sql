-- AbidzarOutdoorcamp - Pengelolaan akun administrator
-- Jalankan setelah backup.txt.

-- Kompatibilitas untuk database versi lama.
alter table public.profiles
  add column if not exists created_at timestamptz not null default now();
alter table public.profiles
  add column if not exists updated_at timestamptz not null default now();

-- Versi lama mungkin memiliki susunan kolom return berbeda dan tidak dapat
-- diganti dengan CREATE OR REPLACE. Hapus signature lama lebih dulu.
drop function if exists public.list_admin_users();
drop function if exists public.add_admin_by_email(text, text);
drop function if exists public.remove_admin_access(uuid);

create or replace function public.list_admin_users()
returns table (
  user_id uuid,
  email text,
  full_name text,
  admin_since timestamptz,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  return query
  select p.id, u.email::text, p.full_name, p.updated_at, p.created_at
  from public.profiles p
  join auth.users u on u.id = p.id
  where lower(trim(p.role)) = 'admin'
  order by p.updated_at, u.email;
end;
$$;

create or replace function public.add_admin_by_email(
  p_email text,
  p_full_name text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id uuid;
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  select id into v_user_id from auth.users
  where lower(email) = lower(trim(p_email)) limit 1;
  if v_user_id is null then
    raise exception 'Akun dengan email tersebut belum terdaftar';
  end if;
  insert into public.profiles(id, full_name, role, updated_at)
  values(v_user_id, nullif(trim(p_full_name), ''), 'admin', now())
  on conflict(id) do update set
    full_name = coalesce(nullif(trim(p_full_name), ''), public.profiles.full_name),
    role = 'admin', updated_at = now();
  return v_user_id;
end;
$$;

create or replace function public.remove_admin_access(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  if p_user_id = auth.uid() then raise exception 'Anda tidak dapat mencabut akses akun sendiri'; end if;
  if (select count(*) from public.profiles where lower(trim(role))='admin') <= 1 then
    raise exception 'Minimal satu administrator harus tetap aktif';
  end if;
  update public.profiles set role='user', updated_at=now()
  where id=p_user_id and lower(trim(role))='admin';
  if not found then raise exception 'Administrator tidak ditemukan'; end if;
end;
$$;

revoke all on function public.list_admin_users() from public;
revoke all on function public.add_admin_by_email(text,text) from public;
revoke all on function public.remove_admin_access(uuid) from public;
grant execute on function public.list_admin_users() to authenticated;
grant execute on function public.add_admin_by_email(text,text) to authenticated;
grant execute on function public.remove_admin_access(uuid) to authenticated;
