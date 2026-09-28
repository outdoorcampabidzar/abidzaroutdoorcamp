-- AOC V32 — HOME SECURITY PIN HARDENING
-- Separate from transaction PIN. Run after the existing auth/security SQL.
-- The homepage PIN is per authenticated account, stored only as a bcrypt hash.

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
returns void
language plpgsql
immutable
set search_path = public, pg_temp
as $$
declare v_pin text := trim(coalesce(p_pin,''));
begin
  if v_pin !~ '^\d{6}$' then raise exception 'PIN keamanan beranda harus tepat 6 digit.'; end if;
  if v_pin in ('000000','111111','222222','333333','444444','555555','666666','777777','888888','999999',
               '123456','654321','123123','321321','121212','112233','223344','334455','445566','556677','667788','778899','987654') then
    raise exception 'PIN terlalu mudah ditebak. Gunakan kombinasi 6 digit yang lebih kuat.';
  end if;
end;
$$;

create or replace function public.set_home_security_pin(p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare v_user_id uuid := auth.uid(); v_pin text := trim(coalesce(p_pin,''));
begin
  if v_user_id is null then raise exception 'Silakan login terlebih dahulu.'; end if;
  perform public.aoc_validate_home_pin(v_pin);
  insert into private.aoc_home_security_pins(user_id,pin_hash,failed_attempts,locked_until,updated_at)
  values(v_user_id, extensions.crypt(v_pin, extensions.gen_salt('bf',12)),0,null,now())
  on conflict(user_id) do update set
    pin_hash=excluded.pin_hash, failed_attempts=0, locked_until=null, updated_at=now();
  delete from private.aoc_home_security_pin_sessions where user_id=v_user_id;
  return jsonb_build_object('success',true,'message','PIN keamanan beranda berhasil disimpan.');
end;
$$;

create or replace function public.has_home_security_pin()
returns boolean
language sql
security definer
stable
set search_path = public, private, pg_temp
as $$
  select exists(select 1 from private.aoc_home_security_pins where user_id=auth.uid());
$$;

create or replace function public.verify_home_security_pin(p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_pin text := trim(coalesce(p_pin,''));
  v_row private.aoc_home_security_pins%rowtype;
  v_attempts integer;
  v_locked_until timestamptz;
  v_until timestamptz;
begin
  if v_user_id is null then raise exception 'Silakan login terlebih dahulu.'; end if;
  if v_pin !~ '^\d{6}$' then
    return jsonb_build_object('success',false,'code','PIN_INVALID_FORMAT','message','PIN harus tepat 6 digit.');
  end if;
  select * into v_row from private.aoc_home_security_pins where user_id=v_user_id for update;
  if not found then
    return jsonb_build_object('success',false,'code','PIN_NOT_SET','message','PIN keamanan beranda belum dibuat.');
  end if;
  if v_row.locked_until is not null and v_row.locked_until > now() then
    return jsonb_build_object('success',false,'code','PIN_LOCKED','message','PIN keamanan beranda terkunci sementara karena terlalu banyak percobaan salah.','locked_until',v_row.locked_until);
  end if;
  if extensions.crypt(v_pin,v_row.pin_hash) <> v_row.pin_hash then
    update private.aoc_home_security_pins
      set failed_attempts=failed_attempts+1,
          locked_until=case when failed_attempts+1 >= 5 then now()+interval '30 minutes' else null end,
          updated_at=now()
      where user_id=v_user_id;
    select failed_attempts,locked_until into v_attempts,v_locked_until from private.aoc_home_security_pins where user_id=v_user_id;
    if v_locked_until is not null and v_locked_until > now() then
      return jsonb_build_object('success',false,'code','PIN_LOCKED','message','5 kali PIN salah. PIN dikunci selama 30 menit.','locked_until',v_locked_until);
    end if;
    return jsonb_build_object('success',false,'code','PIN_WRONG','message','PIN keamanan beranda salah.','remaining_attempts',greatest(0,5-v_attempts));
  end if;
  update private.aoc_home_security_pins set failed_attempts=0,locked_until=null,updated_at=now() where user_id=v_user_id;
  v_until := now()+interval '10 minutes';
  insert into private.aoc_home_security_pin_sessions(user_id,verified_until)
  values(v_user_id,v_until)
  on conflict(user_id) do update set verified_until=excluded.verified_until,created_at=now();
  return jsonb_build_object('success',true,'message','PIN keamanan beranda benar.','verified_until',v_until);
end;
$$;

revoke all on function public.aoc_validate_home_pin(text) from public, anon, authenticated;
revoke all on function public.set_home_security_pin(text) from public, anon, authenticated;
revoke all on function public.has_home_security_pin() from public, anon, authenticated;
revoke all on function public.verify_home_security_pin(text) from public, anon, authenticated;
grant execute on function public.aoc_validate_home_pin(text) to authenticated;
grant execute on function public.set_home_security_pin(text) to authenticated;
grant execute on function public.has_home_security_pin() to authenticated;
grant execute on function public.verify_home_security_pin(text) to authenticated;

notify pgrst,'reload schema';
