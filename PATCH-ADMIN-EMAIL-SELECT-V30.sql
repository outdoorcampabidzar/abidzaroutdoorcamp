-- AbidzarOutdoorcamp V30
-- Email administrator dipilih dari akun yang SUDAH TERDAFTAR.
-- Tidak ada input email manual di Admin Panel.
-- Jalankan setelah PATCH-ADMIN-FEATURE-PERMISSIONS-V29.sql.

create or replace function public.secure_list_admin_candidates()
returns table(
  user_id uuid,
  email text,
  full_name text,
  role text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path=public,auth
as $$
begin
  if not public.has_permission('admin.manage') then
    raise exception 'Izin administrator diperlukan';
  end if;

  return query
  select
    u.id,
    u.email::text,
    p.full_name,
    coalesce(p.role, 'user')::text,
    u.created_at
  from auth.users u
  left join public.profiles p on p.id = u.id
  where coalesce(p.role, 'user') <> 'super_admin'
  order by
    case when nullif(trim(coalesce(p.full_name,'')), '') is null then 1 else 0 end,
    lower(coalesce(nullif(trim(p.full_name), ''), u.email::text));
end;
$$;

revoke all on function public.secure_list_admin_candidates() from public;
grant execute on function public.secure_list_admin_candidates() to authenticated;
