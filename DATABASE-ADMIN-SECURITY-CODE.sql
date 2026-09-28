-- ================================================================
-- AOC ADMIN SECURITY CODE - DOUBLE/3-LAYER PROTECTION
-- LAYERS:
-- 1. Beranda      : existing Home Security PIN (6 digit)
-- 2. Checkout     : existing Transaction PIN (6 digit)
-- 3. Admin Change : Admin Security Code (8 digit)
--
-- Jalankan SEKALI setelah DATABASE-V36-FINAL-PATCH.sql.
-- ================================================================

begin;

create extension if not exists pgcrypto with schema extensions;
create schema if not exists private;

create table if not exists private.aoc_admin_security_codes (
  user_id uuid primary key references auth.users(id) on delete cascade,
  code_hash text not null,
  failed_attempts integer not null default 0,
  locked_until timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists private.aoc_admin_security_sessions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  verified_until timestamptz not null,
  created_at timestamptz not null default now()
);

alter table private.aoc_admin_security_codes enable row level security;
alter table private.aoc_admin_security_sessions enable row level security;
revoke all on private.aoc_admin_security_codes from public, anon, authenticated;
revoke all on private.aoc_admin_security_sessions from public, anon, authenticated;

create or replace function public.aoc_validate_admin_security_code(p_code text)
returns void
language plpgsql
immutable
set search_path=public,pg_temp
as $$
declare v_code text:=trim(coalesce(p_code,''));
begin
  if v_code !~ '^\d{8}$' then
    raise exception 'Kode keamanan admin harus tepat 8 digit.';
  end if;
  if v_code in (
    '00000000','11111111','22222222','33333333','44444444',
    '55555555','66666666','77777777','88888888','99999999',
    '12345678','87654321','12341234','11223344','12121212'
  ) then
    raise exception 'Kode terlalu mudah ditebak. Gunakan kombinasi 8 digit yang lebih kuat.';
  end if;
end;
$$;

create or replace function public.has_admin_security_code()
returns boolean
language sql
security definer
stable
set search_path=public,private,pg_temp
as $$
  select public.is_admin()
     and exists(
       select 1 from private.aoc_admin_security_codes
       where user_id=auth.uid()
     );
$$;

create or replace function public.set_admin_security_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare v_user_id uuid:=auth.uid();
begin
  if v_user_id is null or not public.is_admin() then
    raise exception 'Hanya akun admin yang dapat membuat kode keamanan admin.';
  end if;

  perform public.aoc_validate_admin_security_code(p_code);

  insert into private.aoc_admin_security_codes(
    user_id,code_hash,failed_attempts,locked_until,updated_at
  )
  values(
    v_user_id,
    extensions.crypt(trim(p_code),extensions.gen_salt('bf',12)),
    0,null,now()
  )
  on conflict(user_id) do update set
    code_hash=excluded.code_hash,
    failed_attempts=0,
    locked_until=null,
    updated_at=now();

  delete from private.aoc_admin_security_sessions where user_id=v_user_id;

  return jsonb_build_object(
    'success',true,
    'message','Kode keamanan admin berhasil disimpan.'
  );
end;
$$;

create or replace function public.verify_admin_security_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_user_id uuid:=auth.uid();
  v_row private.aoc_admin_security_codes%rowtype;
  v_attempts integer;
  v_locked_until timestamptz;
begin
  if v_user_id is null or not public.is_admin() then
    return jsonb_build_object(
      'success',false,
      'code','ADMIN_REQUIRED',
      'message','Akses admin diperlukan.'
    );
  end if;

  if trim(coalesce(p_code,'')) !~ '^\d{8}$' then
    return jsonb_build_object(
      'success',false,
      'code','CODE_INVALID_FORMAT',
      'message','Kode admin harus tepat 8 digit.'
    );
  end if;

  select * into v_row
  from private.aoc_admin_security_codes
  where user_id=v_user_id
  for update;

  if not found then
    return jsonb_build_object(
      'success',false,
      'code','CODE_NOT_SET',
      'message','Kode keamanan admin belum dibuat.'
    );
  end if;

  if v_row.locked_until is not null and v_row.locked_until>now() then
    return jsonb_build_object(
      'success',false,
      'code','CODE_LOCKED',
      'message','Kode admin terkunci sementara karena terlalu banyak percobaan salah.',
      'locked_until',v_row.locked_until
    );
  end if;

  if extensions.crypt(trim(p_code),v_row.code_hash)<>v_row.code_hash then
    update private.aoc_admin_security_codes
      set failed_attempts=failed_attempts+1,
          locked_until=case
            when failed_attempts+1>=5 then now()+interval '30 minutes'
            else null
          end,
          updated_at=now()
      where user_id=v_user_id;

    select failed_attempts,locked_until
      into v_attempts,v_locked_until
      from private.aoc_admin_security_codes
      where user_id=v_user_id;

    return jsonb_build_object(
      'success',false,
      'code',case when v_locked_until is not null then 'CODE_LOCKED' else 'CODE_WRONG' end,
      'message',case
        when v_locked_until is not null then 'Terlalu banyak percobaan salah. Kode terkunci 30 menit.'
        else 'Kode keamanan admin salah.'
      end,
      'failed_attempts',v_attempts,
      'locked_until',v_locked_until
    );
  end if;

  update private.aoc_admin_security_codes
    set failed_attempts=0,locked_until=null,updated_at=now()
    where user_id=v_user_id;

  insert into private.aoc_admin_security_sessions(user_id,verified_until)
  values(v_user_id,now()+interval '10 minutes')
  on conflict(user_id) do update set
    verified_until=excluded.verified_until,
    created_at=now();

  return jsonb_build_object(
    'success',true,
    'verified_until',now()+interval '10 minutes',
    'message','Kode admin terverifikasi. Perubahan admin diizinkan selama 10 menit.'
  );
end;
$$;

create or replace function public.has_admin_security_session()
returns boolean
language sql
security definer
stable
set search_path=public,private,pg_temp
as $$
  select public.is_admin()
     and exists(
       select 1
       from private.aoc_admin_security_sessions
       where user_id=auth.uid()
         and verified_until>now()
     );
$$;

create or replace function public.require_admin_security_session()
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  if auth.uid() is null or not public.is_admin() then
    return jsonb_build_object('success',false,'code','ADMIN_REQUIRED','message','Akses admin diperlukan.');
  end if;

  if not public.has_admin_security_session() then
    return jsonb_build_object('success',false,'code','ADMIN_CODE_REQUIRED','message','Masukkan kode keamanan admin sebelum melakukan perubahan.');
  end if;

  return jsonb_build_object('success',true,'message','Sesi keamanan admin aktif.');
end;
$$;

grant execute on function public.aoc_validate_admin_security_code(text) to authenticated;
grant execute on function public.has_admin_security_code() to authenticated;
grant execute on function public.set_admin_security_code(text) to authenticated;
grant execute on function public.verify_admin_security_code(text) to authenticated;
grant execute on function public.has_admin_security_session() to authenticated;
grant execute on function public.require_admin_security_session() to authenticated;


-- Tambahan server-side: menambah/mengubah/mencabut administrator wajib melalui sesi
-- kode admin yang sudah diverifikasi. Membaca daftar admin tetap tidak memerlukan kode.
create or replace function public.secure_set_staff_permissions(a text,b text,c jsonb)
returns uuid
language plpgsql security definer set search_path=public,auth as $$
declare v_id uuid; v_permissions text[]; v_bad text[];
begin
  if not public.has_permission('admin.manage') then raise exception 'Izin administrator diperlukan'; end if;
  if not public.has_admin_security_session() then raise exception 'Kode keamanan admin diperlukan sebelum menambah atau mengubah administrator'; end if;
  select id into v_id from auth.users where lower(email)=lower(trim(a)) limit 1;
  if v_id is null then raise exception 'Akun belum terdaftar'; end if;
  if jsonb_typeof(c)<>'array' then raise exception 'Daftar hak akses tidak valid'; end if;
  select array_agg(x) into v_permissions from jsonb_array_elements_text(c) x;
  if coalesce(array_length(v_permissions,1),0)=0 then raise exception 'Minimal satu fitur harus dipilih'; end if;
  select array_agg(x) into v_bad from unnest(v_permissions) x
    where not (x=any(public.aoc_allowed_admin_permissions_v31()));
  if coalesce(array_length(v_bad,1),0)>0 then raise exception 'Hak akses tidak dikenal: %', array_to_string(v_bad,', '); end if;
  insert into public.profiles(id,full_name,role,updated_at)
    values(v_id,nullif(trim(b),''),'order_admin',now())
    on conflict(id) do update set
      full_name=coalesce(nullif(trim(b),''),public.profiles.full_name),
      role=case when lower(coalesce(public.profiles.role,'')) in ('super_admin','superadmin','admin') then public.profiles.role else 'order_admin' end,
      updated_at=now();
  delete from public.admin_user_permissions where user_id=v_id;
  insert into public.admin_user_permissions(user_id,permission)
    select v_id,x from unnest(v_permissions) x;
  return v_id;
end;
$$;


create or replace function public.secure_remove_staff_role(a uuid)
returns void language plpgsql security definer set search_path=public,auth as $$
begin
  if not public.has_permission('admin.manage') then raise exception 'Izin administrator diperlukan'; end if;
  if not public.has_admin_security_session() then raise exception 'Kode keamanan admin diperlukan sebelum mengubah administrator'; end if;
  if a=auth.uid() then raise exception 'Tidak dapat mencabut role akun sendiri'; end if;
  if exists(select 1 from public.profiles where id=a and lower(coalesce(role,'')) in ('super_admin','superadmin','admin')) then
    raise exception 'Akses Super Admin tidak dapat dicabut dari menu ini';
  end if;
  delete from public.admin_user_permissions where user_id=a;
  update public.profiles set role='user',updated_at=now() where id=a and lower(coalesce(role,''))<>'user';
  if not found then raise exception 'Petugas tidak ditemukan'; end if;
end;
$$;

grant execute on function public.secure_set_staff_permissions(text,text,jsonb),public.secure_remove_staff_role(uuid) to authenticated;

commit;
