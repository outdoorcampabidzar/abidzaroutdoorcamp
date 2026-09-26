-- AOC - FIX ADMIN CUSTOMER PERMISSION
-- Jalankan SETELAH access-security.sql / PATCH-AUTH-ADMIN-SYNC-FINAL.sql.
-- Admin Panel tidak menggunakan PIN transaksi. Patch ini hanya memastikan
-- akun admin mempunyai permission customers.view/customers.manage/reviews.manage.

-- 1. Normalisasi role admin lama.
update public.profiles
set role = 'super_admin', updated_at = now()
where id = auth.uid()
  and lower(trim(role)) in ('admin','superadmin');

-- 2. Pastikan role_permissions tersedia.
create table if not exists public.role_permissions (
  role text not null,
  permission text not null,
  primary key (role, permission)
);

-- 3. Super admin mendapat seluruh akses. Tambahkan permission eksplisit juga
-- agar tetap kompatibel jika helper permission lama sedang aktif di cache.
insert into public.role_permissions(role, permission) values
  ('super_admin','*'),
  ('super_admin','customers.view'),
  ('super_admin','customers.manage'),
  ('super_admin','reviews.manage'),
  ('super_admin','notifications.manage'),
  ('super_admin','orders.view'),
  ('super_admin','orders.manage'),
  ('super_admin','finance.manage'),
  ('super_admin','vouchers.manage'),
  ('super_admin','catalog.manage'),
  ('super_admin','settings.manage'),
  ('super_admin','warehouse.manage')
on conflict do nothing;

-- 4. Helper permission kompatibel dengan role lama.
create or replace function public.has_permission(p_permission text)
returns boolean
language sql stable security definer set search_path=public as $$
  select exists (
    select 1
    from public.profiles p
    left join public.role_permissions rp
      on rp.role = case
        when lower(trim(p.role)) in ('admin','superadmin') then 'super_admin'
        else lower(trim(p.role))
      end
    where p.id = auth.uid()
      and lower(trim(coalesce(p.role,''))) <> 'user'
      and (rp.permission = '*' or rp.permission = p_permission)
  );
$$;

create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path=public as $$
  select public.has_permission('*')
    or exists (
      select 1 from public.profiles p
      where p.id=auth.uid()
        and lower(trim(p.role)) in ('admin','superadmin','super_admin','order_admin','catalog_admin','finance_admin','warehouse_staff')
    );
$$;

grant execute on function public.has_permission(text), public.is_admin() to authenticated;

-- 5. Pastikan RPC pelanggan menggunakan permission yang benar.
create or replace function public.secure_list_customers()
returns table(
  user_id uuid,email text,full_name text,phone text,city text,
  is_verified boolean,is_blocked boolean,blocked_reason text,
  internal_notes text,created_at timestamptz,total_orders bigint,
  total_spent numeric,cancelled_orders bigint,last_order_at timestamptz
)
language plpgsql security definer set search_path=public,auth as $$
begin
  if not public.has_permission('customers.view') then
    raise exception 'Izin pelanggan diperlukan';
  end if;
  return query select * from public.list_customer_summaries();
end; $$;

create or replace function public.secure_admin_update_customer(
  a uuid,b boolean,c boolean,d text default null,e text default null
)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.has_permission('customers.manage') then
    raise exception 'Izin pelanggan diperlukan';
  end if;
  perform public.admin_update_customer(a,b,c,d,e);
end; $$;

grant execute on function public.secure_list_customers(), public.secure_admin_update_customer(uuid,boolean,boolean,text,text) to authenticated;

notify pgrst, 'reload schema';
