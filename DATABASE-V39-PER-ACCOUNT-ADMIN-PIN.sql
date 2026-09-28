-- ================================================================
-- AOC V39 - PER-ACCOUNT ADMIN PIN
-- Jalankan SEKALI di Supabase SQL Editor.
--
-- Tujuan:
-- 1. Setiap akun admin memiliki PIN Admin sendiri.
-- 2. PIN disimpan di DATABASE sebagai bcrypt hash, bukan plaintext.
-- 3. PIN akun A tidak dapat dipakai untuk akun B.
-- 4. Verifikasi dan penyimpanan memakai auth.uid() akun yang login.
-- 5. 5 kali salah -> PIN terkunci 30 menit.
-- 6. Mengganti PIN memerlukan PIN lama.
-- ================================================================

begin;

create extension if not exists pgcrypto with schema extensions;
create schema if not exists private;

create table if not exists private.aoc_admin_security_pins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  pin_hash text not null,
  failed_attempts integer not null default 0,
  locked_until timestamptz,
  updated_at timestamptz not null default now()
);

alter table private.aoc_admin_security_pins enable row level security;

revoke all on private.aoc_admin_security_pins from public, anon, authenticated;

-- Hanya role admin yang boleh memakai RPC ini.
create or replace function public.aoc_is_admin_account()
returns boolean
language sql
security definer
stable
set search_path=public,private,pg_temp
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and lower(coalesce(p.role,'')) in (
        'admin',
        'super_admin',
        'superadmin',
        'order_admin',
        'catalog_admin',
        'finance_admin',
        'warehouse_staff'
      )
  );
$$;

create or replace function public.aoc_validate_admin_pin(p_pin text)
returns void
language plpgsql
immutable
set search_path=public,pg_temp
as $$
declare
  v_pin text := trim(coalesce(p_pin,''));
begin
  if v_pin !~ '^\d{8}$' then
    raise exception 'PIN Admin harus tepat 8 digit.';
  end if;

  if v_pin in (
    '00000000','11111111','22222222','33333333','44444444',
    '55555555','66666666','77777777','88888888','99999999',
    '12345678','87654321','12341234','43214321','11223344',
    '44332211','12121212','12344321'
  ) then
    raise exception 'PIN terlalu mudah ditebak. Gunakan kombinasi 8 digit yang lebih kuat.';
  end if;
end;
$$;

create or replace function public.has_admin_security_pin()
returns boolean
language plpgsql
security definer
stable
set search_path=public,private,pg_temp
as $$
begin
  if auth.uid() is null then
    return false;
  end if;

  if not public.aoc_is_admin_account() then
    return false;
  end if;

  return exists (
    select 1
    from private.aoc_admin_security_pins
    where user_id = auth.uid()
  );
end;
$$;

create or replace function public.set_admin_security_pin(
  p_new_pin text,
  p_current_pin text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,extensions,pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_new_pin text := trim(coalesce(p_new_pin,''));
  v_current_pin text := trim(coalesce(p_current_pin,''));
  v_row private.aoc_admin_security_pins%rowtype;
begin
  if v_user_id is null then
    raise exception 'Silakan login terlebih dahulu.';
  end if;

  if not public.aoc_is_admin_account() then
    raise exception 'Akun ini bukan akun admin.';
  end if;

  perform public.aoc_validate_admin_pin(v_new_pin);

  select *
  into v_row
  from private.aoc_admin_security_pins
  where user_id = v_user_id
  for update;

  if found then
    if v_row.locked_until is not null and v_row.locked_until > now() then
      return jsonb_build_object(
        'success', false,
        'code', 'PIN_LOCKED',
        'message', 'PIN Admin sedang terkunci. Coba lagi setelah masa kunci berakhir.',
        'locked_until', v_row.locked_until
      );
    end if;

    if v_current_pin !~ '^\d{8}$'
       or extensions.crypt(v_current_pin, v_row.pin_hash) <> v_row.pin_hash then
      return jsonb_build_object(
        'success', false,
        'code', 'CURRENT_PIN_WRONG',
        'message', 'PIN Admin lama salah.'
      );
    end if;

    update private.aoc_admin_security_pins
    set
      pin_hash = extensions.crypt(v_new_pin, extensions.gen_salt('bf', 12)),
      failed_attempts = 0,
      locked_until = null,
      updated_at = now()
    where user_id = v_user_id;
  else
    insert into private.aoc_admin_security_pins (
      user_id, pin_hash, failed_attempts, locked_until, updated_at
    )
    values (
      v_user_id,
      extensions.crypt(v_new_pin, extensions.gen_salt('bf', 12)),
      0,
      null,
      now()
    );
  end if;

  return jsonb_build_object(
    'success', true,
    'message', 'PIN Admin akun ini berhasil disimpan ke database.'
  );
end;
$$;

create or replace function public.verify_admin_security_pin(p_pin text)
returns jsonb
language plpgsql
security definer
set search_path=public,private,extensions,pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_pin text := trim(coalesce(p_pin,''));
  v_row private.aoc_admin_security_pins%rowtype;
  v_attempts integer;
  v_locked_until timestamptz;
begin
  if v_user_id is null then
    raise exception 'Silakan login terlebih dahulu.';
  end if;

  if not public.aoc_is_admin_account() then
    return jsonb_build_object(
      'success', false,
      'code', 'NOT_ADMIN',
      'message', 'Akun ini bukan akun admin.'
    );
  end if;

  if v_pin !~ '^\d{8}$' then
    return jsonb_build_object(
      'success', false,
      'code', 'PIN_INVALID_FORMAT',
      'message', 'PIN Admin harus tepat 8 digit.'
    );
  end if;

  select *
  into v_row
  from private.aoc_admin_security_pins
  where user_id = v_user_id
  for update;

  if not found then
    return jsonb_build_object(
      'success', false,
      'code', 'PIN_NOT_SET',
      'message', 'PIN Admin akun ini belum dibuat.'
    );
  end if;

  if v_row.locked_until is not null and v_row.locked_until > now() then
    return jsonb_build_object(
      'success', false,
      'code', 'PIN_LOCKED',
      'message', 'PIN Admin terkunci sementara karena terlalu banyak percobaan salah.',
      'locked_until', v_row.locked_until
    );
  end if;

  if extensions.crypt(v_pin, v_row.pin_hash) <> v_row.pin_hash then
    update private.aoc_admin_security_pins
    set
      failed_attempts = failed_attempts + 1,
      locked_until = case
        when failed_attempts + 1 >= 5
        then now() + interval '30 minutes'
        else null
      end,
      updated_at = now()
    where user_id = v_user_id
    returning failed_attempts, locked_until
    into v_attempts, v_locked_until;

    return jsonb_build_object(
      'success', false,
      'code', case when v_attempts >= 5 then 'PIN_LOCKED' else 'PIN_WRONG' end,
      'message', case
        when v_attempts >= 5
        then 'PIN Admin terkunci selama 30 menit karena 5 kali percobaan salah.'
        else 'PIN Admin salah.'
      end,
      'failed_attempts', v_attempts,
      'locked_until', v_locked_until
    );
  end if;

  update private.aoc_admin_security_pins
  set failed_attempts = 0, locked_until = null, updated_at = now()
  where user_id = v_user_id;

  return jsonb_build_object(
    'success', true,
    'message', 'PIN Admin benar.'
  );
end;
$$;

revoke all on function public.aoc_is_admin_account() from public, anon;
revoke all on function public.aoc_validate_admin_pin(text) from public, anon;
revoke all on function public.has_admin_security_pin() from public, anon;
revoke all on function public.set_admin_security_pin(text,text) from public, anon;
revoke all on function public.verify_admin_security_pin(text) from public, anon;

grant execute on function public.has_admin_security_pin() to authenticated;
grant execute on function public.set_admin_security_pin(text,text) to authenticated;
grant execute on function public.verify_admin_security_pin(text) to authenticated;

-- Hapus RPC global lama jika memang ada. Versi V39 tidak memakainya.
drop function if exists public.set_admin_security_code(text);
drop function if exists public.has_admin_security_code();
drop function if exists public.verify_admin_security_code(text);

commit;
