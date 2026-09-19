-- AOC Transaction PIN Security
-- PIN 6 digit, stored as bcrypt hash, never exposed to client.
-- Run once in Supabase SQL Editor.

create extension if not exists pgcrypto with schema extensions;
create schema if not exists private;

create table if not exists private.aoc_transaction_pins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  pin_hash text not null,
  failed_attempts integer not null default 0,
  locked_until timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists private.aoc_transaction_pin_sessions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  verified_until timestamptz not null,
  created_at timestamptz not null default now()
);

alter table private.aoc_transaction_pins enable row level security;
alter table private.aoc_transaction_pin_sessions enable row level security;

revoke all on private.aoc_transaction_pins from public, anon, authenticated;
revoke all on private.aoc_transaction_pin_sessions from public, anon, authenticated;

-- Create or replace the user's transaction PIN. Existing logged-in users can use
-- this function from their profile to create/reset the PIN.
create or replace function public.set_transaction_pin(p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_pin text := trim(coalesce(p_pin, ''));
begin
  if v_user_id is null then
    raise exception 'Silakan login terlebih dahulu';
  end if;
  if v_pin !~ '^\d{6}$' then
    raise exception 'PIN transaksi harus tepat 6 digit.';
  end if;

  insert into private.aoc_transaction_pins(user_id, pin_hash, failed_attempts, locked_until, updated_at)
  values (v_user_id, extensions.crypt(v_pin, extensions.gen_salt('bf', 10)), 0, null, now())
  on conflict (user_id) do update set
    pin_hash = excluded.pin_hash,
    failed_attempts = 0,
    locked_until = null,
    updated_at = now();

  delete from private.aoc_transaction_pin_sessions where user_id = v_user_id;
  return jsonb_build_object('success', true, 'message', 'PIN transaksi berhasil disimpan.');
end;
$$;

create or replace function public.has_transaction_pin()
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1 from private.aoc_transaction_pins
    where user_id = (select auth.uid())
  );
$$;

create or replace function public.verify_transaction_pin(p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_pin text := trim(coalesce(p_pin, ''));
  v_row private.aoc_transaction_pins%rowtype;
  v_until timestamptz;
  v_attempts integer;
  v_locked_until timestamptz;
begin
  if v_user_id is null then
    raise exception 'Silakan login terlebih dahulu';
  end if;
  if v_pin !~ '^\d{6}$' then
    return jsonb_build_object('success', false, 'message', 'PIN harus 6 digit.');
  end if;

  select * into v_row
  from private.aoc_transaction_pins
  where user_id = v_user_id
  for update;

  if not found then
    return jsonb_build_object('success', false, 'code', 'PIN_NOT_SET', 'message', 'PIN transaksi belum dibuat. Silakan buat PIN di Profil Saya.');
  end if;

  if v_row.locked_until is not null and v_row.locked_until > now() then
    return jsonb_build_object(
      'success', false,
      'code', 'PIN_LOCKED',
      'message', 'PIN terkunci sementara karena terlalu banyak percobaan salah.',
      'locked_until', v_row.locked_until
    );
  end if;

  if extensions.crypt(v_pin, v_row.pin_hash) <> v_row.pin_hash then
    update private.aoc_transaction_pins
    set failed_attempts = failed_attempts + 1,
        locked_until = case when failed_attempts + 1 >= 5 then now() + interval '15 minutes' else null end,
        updated_at = now()
    where user_id = v_user_id;

    select failed_attempts, locked_until into v_attempts, v_locked_until
    from private.aoc_transaction_pins where user_id = v_user_id;

    if v_locked_until is not null and v_locked_until > now() then
      return jsonb_build_object('success', false, 'code', 'PIN_LOCKED', 'message', '5 kali PIN salah. PIN dikunci selama 15 menit.', 'locked_until', v_locked_until);
    end if;

    return jsonb_build_object('success', false, 'code', 'PIN_WRONG', 'message', 'PIN transaksi salah.', 'remaining_attempts', greatest(0, 5 - v_attempts));
  end if;

  update private.aoc_transaction_pins
  set failed_attempts = 0, locked_until = null, updated_at = now()
  where user_id = v_user_id;

  v_until := now() + interval '2 minutes';
  insert into private.aoc_transaction_pin_sessions(user_id, verified_until)
  values (v_user_id, v_until)
  on conflict (user_id) do update set verified_until = excluded.verified_until, created_at = now();

  return jsonb_build_object('success', true, 'message', 'PIN transaksi benar.', 'verified_until', v_until);
end;
$$;

-- This trigger is the server-side gate. Client-side PIN UI alone is not enough:
-- authenticated customer inserts into orders only after a successful PIN verification.
create or replace function public.aoc_require_transaction_pin_for_customer_order()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_verified boolean := false;
begin
  -- Service-role/background jobs/admin server processes have no auth.uid().
  -- Customer-created orders must have a fresh PIN verification.
  if v_user_id is null or new.user_id is distinct from v_user_id then
    return new;
  end if;

  select exists (
    select 1
    from private.aoc_transaction_pin_sessions
    where user_id = v_user_id
      and verified_until > now()
  ) into v_verified;

  if not v_verified then
    raise exception 'PIN transaksi wajib diverifikasi sebelum membuat pesanan.';
  end if;

  delete from private.aoc_transaction_pin_sessions where user_id = v_user_id;
  return new;
end;
$$;

drop trigger if exists aoc_require_transaction_pin on public.orders;
create trigger aoc_require_transaction_pin
before insert on public.orders
for each row
execute function public.aoc_require_transaction_pin_for_customer_order();

revoke all on function public.set_transaction_pin(text) from public, anon;
revoke all on function public.has_transaction_pin() from public, anon;
revoke all on function public.verify_transaction_pin(text) from public, anon;
grant execute on function public.set_transaction_pin(text) to authenticated;
grant execute on function public.has_transaction_pin() to authenticated;
grant execute on function public.verify_transaction_pin(text) to authenticated;

notify pgrst, 'reload schema';
