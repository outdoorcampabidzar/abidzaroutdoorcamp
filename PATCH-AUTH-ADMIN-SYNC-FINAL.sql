-- AOC AUTH + ADMIN SYNC FINAL
-- Jalankan TERAKHIR setelah access-security.sql dan PATCH-AUTH-LOGIN-DAN-AKTIVASI-KODE-6-DIGIT.sql.
-- Menyatukan role lama "admin" dengan sistem role baru "super_admin" tanpa
-- memutus akun lama. Semua pemeriksaan admin memakai sumber yang sama.

-- 1) Normalisasi role lama.
update public.profiles
set role='super_admin', updated_at=now()
where lower(trim(role)) in ('admin','superadmin');

-- 2) Pastikan permission super_admin lengkap.
insert into public.role_permissions(role, permission)
select 'super_admin', permission
from (values
  ('*')
) v(permission)
on conflict do nothing;

-- 3) is_admin kompatibel dengan role lama dan role baru.
create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path=public as $$
  select exists (
    select 1 from public.profiles p
    where p.id=auth.uid()
      and p.role in ('super_admin','superadmin','admin','order_admin','catalog_admin','finance_admin','warehouse_staff')
  );
$$;

-- 4) Permission helper selalu membaca role yang sama.
create or replace function public.has_permission(p_permission text)
returns boolean
language sql stable security definer set search_path=public as $$
  select exists (
    select 1
    from public.profiles p
    left join public.role_permissions rp on rp.role = case when p.role in ('admin','superadmin') then 'super_admin' else p.role end
    left join public.admin_security_verifications v on v.user_id=p.id
    where p.id=auth.uid()
      and p.role <> 'user'
      and (v.verified_until > now() or p.role in ('admin','superadmin'))
      and (rp.permission='*' or rp.permission=p_permission)
  );
$$;

-- 5) Login code harus membuat verifikasi admin untuk semua nama role yang didukung.
create or replace function public.verify_login_code(p_code text)
returns boolean language plpgsql security definer set search_path=public,pg_temp as $$
declare ok boolean := false; attempts integer; v_role text;
begin
  if auth.uid() is null then raise exception 'Anda belum login ke Supabase Auth'; end if;
  select login_attempts into attempts
  from public.account_security_codes
  where user_id=auth.uid() and login_code is not null and login_expires_at>now()
  for update;
  if attempts is null then return false; end if;

  update public.account_security_codes
  set login_attempts=login_attempts+1,updated_at=now()
  where user_id=auth.uid() and login_code=trim(p_code)
    and login_expires_at>now() and login_used_at is null and login_attempts<5;
  ok := found;

  if ok then
    update public.account_security_codes
    set login_used_at=now(),login_code=null,login_expires_at=null,updated_at=now()
    where user_id=auth.uid();

    select lower(trim(role)) into v_role from public.profiles where id=auth.uid();
    if v_role in ('admin','superadmin','super_admin','order_admin','catalog_admin','finance_admin','warehouse_staff') then
      insert into public.admin_security_verifications(user_id,verified_at,verified_until)
      values(auth.uid(),now(),now()+interval '12 hours')
      on conflict(user_id) do update set verified_at=now(),verified_until=now()+interval '12 hours';
    end if;
  elsif attempts+1>=5 then
    update public.account_security_codes
    set login_code=null,login_expires_at=null,updated_at=now()
    where user_id=auth.uid();
  end if;
  return ok;
end; $$;

-- 6) Security check admin harus konsisten dengan verify_login_code.
create or replace function public.admin_security_check()
returns boolean language sql stable security definer set search_path=public as $$
select exists(
  select 1 from public.profiles p
  join public.admin_security_verifications v on v.user_id=p.id
  where p.id=auth.uid()
    and p.role in ('admin','superadmin','super_admin','order_admin','catalog_admin','finance_admin','warehouse_staff')
    and v.verified_until>now()
); $$;

create or replace function public.get_my_staff_permissions()
returns jsonb language sql stable security definer set search_path=public as $$
select jsonb_build_object(
  'role',coalesce(p.role,'user'),
  'permissions',coalesce((select jsonb_agg(rp.permission) from public.role_permissions rp where rp.role=case when p.role in ('admin','superadmin') then 'super_admin' else p.role end),'[]'::jsonb)
)
from public.profiles p where p.id=auth.uid();
$$;

grant execute on function public.is_admin(),public.has_permission(text),public.admin_security_check(),public.get_my_staff_permissions(),public.verify_login_code(text) to authenticated;
notify pgrst,'reload schema';
