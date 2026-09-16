-- AOC AUTH FIX: kode aktivasi saat registrasi + kode acak setiap login.
-- FIX untuk ERROR 42P13: cannot change return type of existing function.
-- Jalankan file ini SEKALI di Supabase SQL Editor.
-- Jika fungsi lama sudah ada dengan return type berbeda, fungsi lama dihapus
-- berdasarkan signature lalu dibuat ulang dengan return type TEXT/BOOLEAN.
-- Setelah itu di Supabase: Authentication -> Sign In / Providers -> Email -> Confirm email = OFF.

create table if not exists public.account_security_codes (
  user_id uuid primary key references auth.users(id) on delete cascade,
  activation_code text,
  activation_expires_at timestamptz,
  activation_used_at timestamptz,
  login_code text,
  login_expires_at timestamptz,
  login_used_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.account_security_codes enable row level security;
revoke all on public.account_security_codes from anon, authenticated;

-- Hapus fungsi lama terlebih dahulu karena PostgreSQL tidak mengizinkan
-- CREATE OR REPLACE mengubah tipe return fungsi yang sudah ada.
drop function if exists public.issue_account_activation_code();
drop function if exists public.verify_account_activation_code(text);
drop function if exists public.issue_login_code();
drop function if exists public.verify_login_code(text);

create function public.issue_account_activation_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  if auth.uid() is null then
    raise exception 'Anda belum login ke Supabase Auth';
  end if;

  v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');

  insert into public.account_security_codes (
    user_id, activation_code, activation_expires_at,
    activation_used_at, updated_at
  )
  values (
    auth.uid(), v_code, now() + interval '30 minutes',
    null, now()
  )
  on conflict (user_id) do update set
    activation_code = excluded.activation_code,
    activation_expires_at = excluded.activation_expires_at,
    activation_used_at = null,
    updated_at = now();

  return v_code;
end;
$$;

create function public.verify_account_activation_code(p_code text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Anda belum login ke Supabase Auth';
  end if;

  update public.account_security_codes
  set
    activation_used_at = now(),
    activation_code = null,
    activation_expires_at = null,
    updated_at = now()
  where user_id = auth.uid()
    and activation_code = trim(p_code)
    and activation_expires_at > now()
    and activation_used_at is null;

  return found;
end;
$$;

create function public.issue_login_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  if auth.uid() is null then
    raise exception 'Anda belum login ke Supabase Auth';
  end if;

  v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');

  insert into public.account_security_codes (
    user_id, login_code, login_expires_at,
    login_used_at, updated_at
  )
  values (
    auth.uid(), v_code, now() + interval '10 minutes',
    null, now()
  )
  on conflict (user_id) do update set
    login_code = excluded.login_code,
    login_expires_at = excluded.login_expires_at,
    login_used_at = null,
    updated_at = now();

  return v_code;
end;
$$;

create function public.verify_login_code(p_code text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Anda belum login ke Supabase Auth';
  end if;

  update public.account_security_codes
  set
    login_used_at = now(),
    login_code = null,
    login_expires_at = null,
    updated_at = now()
  where user_id = auth.uid()
    and login_code = trim(p_code)
    and login_expires_at > now()
    and login_used_at is null;

  return found;
end;
$$;

grant execute on function public.issue_account_activation_code() to authenticated;
grant execute on function public.verify_account_activation_code(text) to authenticated;
grant execute on function public.issue_login_code() to authenticated;
grant execute on function public.verify_login_code(text) to authenticated;

notify pgrst, 'reload schema';

-- Tes setelah menjalankan script:
-- SELECT pg_get_function_result(p.oid), p.proname
-- FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
-- WHERE n.nspname='public'
-- AND p.proname IN ('issue_account_activation_code','verify_account_activation_code','issue_login_code','verify_login_code');
