-- AOC AUTH SECURITY V2
-- Jalankan SETELAH access-security.sql.
-- Fitur: kode 6 digit acak, sekali pakai, expiry, rate limit penerbitan,
-- maksimum 5 percobaan, dan status verifikasi server-side untuk staff/admin.

create table if not exists public.account_security_codes (
  user_id uuid primary key references auth.users(id) on delete cascade,
  activation_code text,
  activation_expires_at timestamptz,
  activation_used_at timestamptz,
  activation_attempts integer not null default 0,
  login_code text,
  login_expires_at timestamptz,
  login_used_at timestamptz,
  login_attempts integer not null default 0,
  last_issued_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.account_security_codes enable row level security;
revoke all on public.account_security_codes from anon, authenticated;

alter table public.account_security_codes
  add column if not exists activation_attempts integer not null default 0;

alter table public.account_security_codes
  add column if not exists login_attempts integer not null default 0;
alter table public.account_security_codes
  add column if not exists last_issued_at timestamptz;

create table if not exists public.admin_security_verifications (
  user_id uuid primary key references auth.users(id) on delete cascade,
  verified_at timestamptz not null default now(),
  verified_until timestamptz not null
);
alter table public.admin_security_verifications enable row level security;
revoke all on public.admin_security_verifications from anon, authenticated;

-- Jangan ubah return type fungsi yang sudah ada; signature tetap sama.
create or replace function public.issue_account_activation_code()
returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare v_code text; v_last timestamptz; v_n bigint;
begin
  if auth.uid() is null then raise exception 'Anda belum login ke Supabase Auth'; end if;
  select last_issued_at into v_last from public.account_security_codes where user_id=auth.uid() for update;
  if v_last is not null and v_last > now() - interval '60 seconds' then
    raise exception 'Tunggu 60 detik sebelum meminta kode baru';
  end if;
  v_n := floor(random() * 1000000)::bigint;
  v_code := lpad(v_n::text, 6, '0');
  insert into public.account_security_codes(user_id,activation_code,activation_expires_at,activation_used_at,activation_attempts,last_issued_at,updated_at)
  values(auth.uid(),v_code,now()+interval '10 minutes',null,0,now(),now())
  on conflict(user_id) do update set activation_code=excluded.activation_code,activation_expires_at=excluded.activation_expires_at,activation_used_at=null,activation_attempts=0,last_issued_at=excluded.last_issued_at,updated_at=now();
  return v_code;
end; $$;

create or replace function public.verify_account_activation_code(p_code text)
returns boolean language plpgsql security definer set search_path=public,pg_temp as $$
declare ok boolean := false; attempts integer;
begin
  if auth.uid() is null then raise exception 'Anda belum login ke Supabase Auth'; end if;
  select activation_attempts into attempts from public.account_security_codes where user_id=auth.uid() and activation_code is not null and activation_expires_at>now() for update;
  if attempts is null then return false; end if;
  update public.account_security_codes set activation_attempts=activation_attempts+1,updated_at=now()
    where user_id=auth.uid() and activation_code=trim(p_code) and activation_expires_at>now() and activation_used_at is null and activation_attempts<5;
  ok := found;
  if ok then
    update public.account_security_codes set activation_used_at=now(),activation_code=null,activation_expires_at=null,updated_at=now() where user_id=auth.uid();
  elsif attempts+1>=5 then
    update public.account_security_codes set activation_code=null,activation_expires_at=null,updated_at=now() where user_id=auth.uid();
  end if;
  return ok;
end; $$;

create or replace function public.issue_login_code()
returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare v_code text; v_last timestamptz; v_n bigint;
begin
  if auth.uid() is null then raise exception 'Anda belum login ke Supabase Auth'; end if;
  select last_issued_at into v_last from public.account_security_codes where user_id=auth.uid() for update;
  if v_last is not null and v_last > now() - interval '60 seconds' then
    raise exception 'Tunggu 60 detik sebelum meminta kode baru';
  end if;
  v_n := floor(random() * 1000000)::bigint;
  v_code := lpad(v_n::text, 6, '0');
  insert into public.account_security_codes(user_id,login_code,login_expires_at,login_used_at,login_attempts,last_issued_at,updated_at)
  values(auth.uid(),v_code,now()+interval '10 minutes',null,0,now(),now())
  on conflict(user_id) do update set login_code=excluded.login_code,login_expires_at=excluded.login_expires_at,login_used_at=null,login_attempts=0,last_issued_at=excluded.last_issued_at,updated_at=now();
  return v_code;
end; $$;

create or replace function public.verify_login_code(p_code text)
returns boolean language plpgsql security definer set search_path=public,pg_temp as $$
declare ok boolean := false; attempts integer; v_role text;
begin
  if auth.uid() is null then raise exception 'Anda belum login ke Supabase Auth'; end if;
  select login_attempts into attempts from public.account_security_codes where user_id=auth.uid() and login_code is not null and login_expires_at>now() for update;
  if attempts is null then return false; end if;
  update public.account_security_codes set login_attempts=login_attempts+1,updated_at=now()
    where user_id=auth.uid() and login_code=trim(p_code) and login_expires_at>now() and login_used_at is null and login_attempts<5;
  ok := found;
  if ok then
    update public.account_security_codes set login_used_at=now(),login_code=null,login_expires_at=null,updated_at=now() where user_id=auth.uid();
    select role into v_role from public.profiles where id=auth.uid();
    if v_role in ('super_admin','order_admin','catalog_admin','finance_admin','warehouse_staff') then
      insert into public.admin_security_verifications(user_id,verified_at,verified_until)
      values(auth.uid(),now(),now()+interval '12 hours')
      on conflict(user_id) do update set verified_at=now(),verified_until=now()+interval '12 hours';
    end if;
  elsif attempts+1>=5 then
    update public.account_security_codes set login_code=null,login_expires_at=null,updated_at=now() where user_id=auth.uid();
  end if;
  return ok;
end; $$;

create or replace function public.admin_security_check()
returns boolean language sql stable security definer set search_path=public as $$
select exists(
  select 1 from public.profiles p
  join public.admin_security_verifications v on v.user_id=p.id
  where p.id=auth.uid()
    and p.role in ('super_admin','order_admin','catalog_admin','finance_admin','warehouse_staff')
    and v.verified_until>now()
); $$;

-- Semua permission staff sekarang membutuhkan verifikasi kode server-side.
create or replace function public.has_permission(p_permission text)
returns boolean language sql stable security definer set search_path=public as $$
select exists(
  select 1
  from public.profiles p
  join public.role_permissions rp on rp.role=p.role
  left join public.admin_security_verifications v on v.user_id=p.id
  where p.id=auth.uid()
    and (p.role='user' or v.verified_until>now())
    and (rp.permission='*' or rp.permission=p_permission)
); $$;

grant execute on function public.issue_account_activation_code() to authenticated;
grant execute on function public.verify_account_activation_code(text) to authenticated;
grant execute on function public.issue_login_code() to authenticated;
grant execute on function public.verify_login_code(text) to authenticated;
grant execute on function public.admin_security_check() to authenticated;

notify pgrst,'reload schema';
