-- AbidzarOutdoorcamp V29 - Hak akses admin per fitur / per akun
-- Jalankan SETELAH access-security.sql dan SQL admin lainnya.
-- Tidak menghapus data akun. Super Admin tetap memiliki semua akses.

create table if not exists public.admin_user_permissions (
  user_id uuid not null references auth.users(id) on delete cascade,
  permission text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, permission)
);

alter table public.admin_user_permissions enable row level security;
drop policy if exists admin_user_permissions_no_direct_access on public.admin_user_permissions;
create policy admin_user_permissions_no_direct_access
  on public.admin_user_permissions
  for all using (false) with check (false);

-- Hak yang boleh dipilih dari UI.
create or replace function public.aoc_allowed_admin_permissions()
returns text[] language sql immutable as $$
  select array[
    'catalog.manage','orders.view','orders.manage','warehouse.manage',
    'finance.manage','vouchers.manage','coinshop.manage','settings.manage',
    'customers.view','customers.manage','reviews.manage','notifications.manage',
    'trip_participants.manage','reports.view','admin.manage','audit.view'
  ];
$$;

-- Jika akun memiliki baris per-user, baris tersebut menjadi daftar akses final.
-- Jika belum ada override per-user, role_permissions tetap menjadi fallback.
create or replace function public.get_my_staff_permissions()
returns jsonb
language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'role', coalesce(p.role,'user'),
    'permissions',
      case
        when p.role='super_admin' then '["*"]'::jsonb
        when exists(select 1 from public.admin_user_permissions up where up.user_id=p.id) then
          coalesce((select jsonb_agg(up.permission order by up.permission) from public.admin_user_permissions up where up.user_id=p.id),'[]'::jsonb)
        else
          coalesce((select jsonb_agg(rp.permission order by rp.permission) from public.role_permissions rp where rp.role=p.role),'[]'::jsonb)
      end
  )
  from public.profiles p where p.id=auth.uid();
$$;

create or replace function public.has_permission(p_permission text)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(
    select 1 from public.profiles p
    where p.id=auth.uid() and (
      p.role='super_admin'
      or (
        exists(select 1 from public.admin_user_permissions up where up.user_id=p.id)
        and exists(select 1 from public.admin_user_permissions up where up.user_id=p.id and up.permission in ('*',p_permission))
      )
      or (
        not exists(select 1 from public.admin_user_permissions up where up.user_id=p.id)
        and exists(select 1 from public.role_permissions rp where rp.role=p.role and rp.permission in ('*',p_permission))
      )
    )
  );
$$;

drop function if exists public.secure_list_staff_users();
create or replace function public.secure_list_staff_users()
returns table(user_id uuid,email text,full_name text,role text,created_at timestamptz,permissions jsonb)
language plpgsql security definer set search_path=public,auth as $$
begin
  if not public.has_permission('admin.manage') then raise exception 'Izin administrator diperlukan'; end if;
  return query
  select p.id,u.email::text,p.full_name,p.role,p.created_at,
    case when p.role='super_admin' then '["*"]'::jsonb
      when exists(select 1 from public.admin_user_permissions up where up.user_id=p.id) then coalesce((select jsonb_agg(up.permission order by up.permission) from public.admin_user_permissions up where up.user_id=p.id),'[]'::jsonb)
      else coalesce((select jsonb_agg(rp.permission order by rp.permission) from public.role_permissions rp where rp.role=p.role),'[]'::jsonb) end
  from public.profiles p join auth.users u on u.id=p.id
  where p.role<>'user' order by p.created_at;
end;
$$;

create or replace function public.secure_set_staff_permissions(a text,b text,c jsonb)
returns uuid
language plpgsql security definer set search_path=public,auth as $$
declare v_id uuid; v_permissions text[]; v_bad text[];
begin
  if not public.has_permission('admin.manage') then raise exception 'Izin administrator diperlukan'; end if;
  select id into v_id from auth.users where lower(email)=lower(trim(a)) limit 1;
  if v_id is null then raise exception 'Akun belum terdaftar'; end if;
  if jsonb_typeof(c)<>'array' then raise exception 'Daftar hak akses tidak valid'; end if;
  select array_agg(x) into v_permissions from jsonb_array_elements_text(c) x;
  if coalesce(array_length(v_permissions,1),0)=0 then raise exception 'Minimal satu fitur harus dipilih'; end if;
  select array_agg(x) into v_bad from unnest(v_permissions) x where not (x=any(public.aoc_allowed_admin_permissions()));
  if coalesce(array_length(v_bad,1),0)>0 then raise exception 'Hak akses tidak dikenal: %', array_to_string(v_bad,', '); end if;
  insert into public.profiles(id,full_name,role,updated_at) values(v_id,nullif(trim(b),''),'order_admin',now())
    on conflict(id) do update set full_name=coalesce(nullif(trim(b),''),public.profiles.full_name),role=case when public.profiles.role='super_admin' then public.profiles.role else 'order_admin' end,updated_at=now();
  delete from public.admin_user_permissions where user_id=v_id;
  insert into public.admin_user_permissions(user_id,permission) select v_id,x from unnest(v_permissions) x;
  return v_id;
end;
$$;

create or replace function public.secure_remove_staff_role(a uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.has_permission('admin.manage') then raise exception 'Izin administrator diperlukan'; end if;
  if a=auth.uid() then raise exception 'Tidak dapat mencabut role akun sendiri'; end if;
  if exists(select 1 from public.profiles where id=a and role='super_admin') then raise exception 'Akses Super Admin tidak dapat dicabut dari menu ini'; end if;
  delete from public.admin_user_permissions where user_id=a;
  update public.profiles set role='user',updated_at=now() where id=a and role<>'user';
  if not found then raise exception 'Petugas tidak ditemukan'; end if;
end;
$$;

revoke all on function public.aoc_allowed_admin_permissions() from public;
revoke all on function public.get_my_staff_permissions() from public;
revoke all on function public.has_permission(text) from public;
revoke all on function public.secure_list_staff_users() from public;
revoke all on function public.secure_set_staff_permissions(text,text,jsonb) from public;
revoke all on function public.secure_remove_staff_role(uuid) from public;
grant execute on function public.get_my_staff_permissions(),public.has_permission(text) to authenticated;
grant execute on function public.secure_list_staff_users(),public.secure_set_staff_permissions(text,text,jsonb),public.secure_remove_staff_role(uuid) to authenticated;

notify pgrst,'reload schema';
