-- AOC FIX: login/activation code tanpa ketergantungan gen_random_bytes/pgcrypto
-- Jalankan file ini di Supabase SQL Editor.
-- Aman dijalankan setelah patch auth sebelumnya.

create or replace function public.issue_account_activation_code()
returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_code text; v_last timestamptz; v_n bigint;
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

create or replace function public.issue_login_code()
returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_code text; v_last timestamptz; v_n bigint;
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

grant execute on function public.issue_account_activation_code() to authenticated;
grant execute on function public.issue_login_code() to authenticated;

notify pgrst, 'reload schema';
