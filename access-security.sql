-- AbidzarOutdoorcamp - Hak akses bertingkat, RLS, dan audit log
-- Jalankan PALING AKHIR setelah seluruh file SQL fitur lainnya.

do $$ declare c record; begin
  for c in select conname from pg_constraint where conrelid='public.profiles'::regclass and contype='c' and pg_get_constraintdef(oid) ilike '%role%'
  loop execute format('alter table public.profiles drop constraint %I',c.conname); end loop;
end $$;
update public.profiles set role=lower(trim(role));
update public.profiles set role='super_admin' where role='admin';
update public.profiles set role='user' where role not in ('user','super_admin','order_admin','catalog_admin','finance_admin','warehouse_staff');
alter table public.profiles add constraint profiles_role_access_check check(role in ('user','super_admin','order_admin','catalog_admin','finance_admin','warehouse_staff'));

create table if not exists public.role_permissions(role text not null,permission text not null,primary key(role,permission));
insert into public.role_permissions(role,permission) values
('super_admin','*'),('order_admin','orders.view'),('order_admin','orders.manage'),('order_admin','customers.view'),('order_admin','customers.manage'),('order_admin','notifications.manage'),('order_admin','reviews.manage'),('order_admin','trip_participants.manage'),
('catalog_admin','catalog.manage'),('catalog_admin','settings.manage'),('catalog_admin','reviews.manage'),
('finance_admin','orders.view'),('finance_admin','finance.manage'),('finance_admin','vouchers.manage'),('finance_admin','reports.view'),
('warehouse_staff','orders.view'),('warehouse_staff','warehouse.manage'),('warehouse_staff','trip_participants.manage')
on conflict do nothing;

create or replace function public.has_permission(p_permission text) returns boolean language sql stable security definer set search_path=public as $$
select exists(select 1 from public.profiles p join public.role_permissions rp on rp.role=p.role where p.id=auth.uid() and (rp.permission='*' or rp.permission=p_permission)); $$;
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$ select public.has_permission('*') or exists(select 1 from public.profiles where id=auth.uid() and role in ('order_admin','catalog_admin','finance_admin','warehouse_staff')); $$;
create or replace function public.get_my_staff_permissions() returns jsonb language sql stable security definer set search_path=public as $$
select jsonb_build_object('role',coalesce(p.role,'user'),'permissions',coalesce((select jsonb_agg(permission) from public.role_permissions where role=p.role),'[]'::jsonb)) from public.profiles p where p.id=auth.uid(); $$;

create table if not exists public.admin_activity_logs(
 id bigint generated always as identity primary key,admin_user_id uuid references auth.users(id) on delete set null,admin_role text,action text not null,table_name text not null,record_id text,old_data jsonb,new_data jsonb,created_at timestamptz not null default now()
);
alter table public.admin_activity_logs enable row level security;
create or replace function public.audit_admin_change() returns trigger language plpgsql security definer set search_path=public as $$
declare v_role text;v_old jsonb;v_new jsonb;v_id text;
begin select role into v_role from public.profiles where id=auth.uid(); if v_role is null or v_role='user' then return coalesce(new,old); end if;
v_old:=case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end;v_new:=case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end;v_id:=coalesce(v_new->>'id',v_old->>'id',v_new->>'order_id',v_old->>'order_id');
insert into public.admin_activity_logs(admin_user_id,admin_role,action,table_name,record_id,old_data,new_data) values(auth.uid(),v_role,lower(tg_op),tg_table_name,v_id,v_old,v_new);return coalesce(new,old);end; $$;
do $$ declare t text; begin foreach t in array array['items','item_categories','item_images','item_variants','inventory_units','item_price_tiers','trip_details','trip_participants','orders','vouchers','voucher_items','site_settings','website_ratings','customer_notifications','order_refunds','order_returns','profiles'] loop if to_regclass('public.'||t) is not null then execute format('drop trigger if exists audit_admin_change_trigger on public.%I',t);execute format('create trigger audit_admin_change_trigger after insert or update or delete on public.%I for each row execute function public.audit_admin_change()',t);end if;end loop;end $$;

-- Tutup RPC admin lama; frontend memakai wrapper aman di bawah.
revoke execute on function public.admin_update_order_status(uuid,text,text) from authenticated;
revoke execute on function public.admin_manage_order(uuid,text,numeric,text,text,uuid,integer) from authenticated;
revoke execute on function public.admin_update_customer(uuid,boolean,boolean,text,text) from authenticated;
revoke execute on function public.admin_moderate_website_rating(uuid,boolean,text) from authenticated;
revoke execute on function public.admin_generate_reminders() from authenticated;
revoke execute on function public.admin_mark_notification_sent(uuid) from authenticated;
revoke execute on function public.admin_update_trip_participant_status(uuid,text) from authenticated;
revoke execute on function public.list_customer_summaries() from authenticated;
revoke execute on function public.list_admin_website_ratings() from authenticated;
revoke execute on function public.list_admin_users() from authenticated;
revoke execute on function public.add_admin_by_email(text,text) from authenticated;
revoke execute on function public.remove_admin_access(uuid) from authenticated;
revoke execute on function public.admin_save_site_settings(jsonb) from authenticated;

create or replace function public.secure_admin_save_site_settings(p_settings jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_settings jsonb;
begin
  if not (public.has_permission('settings.manage') or public.has_permission('*')) then
    raise exception 'Izin pengaturan website diperlukan';
  end if;
  if p_settings is null or jsonb_typeof(p_settings)<>'object' then
    raise exception 'Format pengaturan tidak valid';
  end if;
  v_settings := p_settings || jsonb_build_object(
    'whatsapp_number',regexp_replace(coalesce(p_settings->>'whatsapp_number',''),'[^0-9]','','g'),
    'admin_1_whatsapp',regexp_replace(coalesce(p_settings->>'admin_1_whatsapp',''),'[^0-9]','','g'),
    'admin_2_whatsapp',regexp_replace(coalesce(p_settings->>'admin_2_whatsapp',''),'[^0-9]','','g'),
    'admin_3_whatsapp',regexp_replace(coalesce(p_settings->>'admin_3_whatsapp',''),'[^0-9]','','g'),
    'payment_method_rental',case when coalesce(p_settings->>'payment_method_rental','') in ('qrisorkut','qrisdana','qrisgopay','qrisshopeepay') then p_settings->>'payment_method_rental' else 'qrisorkut' end,
    'payment_method_sale',case when coalesce(p_settings->>'payment_method_sale','') in ('qrisorkut','qrisdana','qrisgopay','qrisshopeepay') then p_settings->>'payment_method_sale' else 'qrisdana' end,
    'payment_method',case when coalesce(p_settings->>'payment_method','') in ('qrisorkut','qrisdana','qrisgopay','qrisshopeepay') then p_settings->>'payment_method' else coalesce(p_settings->>'payment_method_rental','qrisorkut') end
  );
  insert into public.site_settings(id,settings,updated_at,updated_by)
  values('main',v_settings,now(),auth.uid())
  on conflict(id) do update set settings=excluded.settings,
    updated_at=excluded.updated_at,updated_by=excluded.updated_by;
  return v_settings;
end$$;
revoke all on function public.secure_admin_save_site_settings(jsonb) from public;
grant execute on function public.secure_admin_save_site_settings(jsonb) to authenticated;

create or replace function public.secure_admin_update_order_status(a uuid,b text,c text default null) returns void language plpgsql security definer set search_path=public as $$begin if not public.has_permission('orders.manage') then raise exception 'Izin pesanan diperlukan';end if;perform public.admin_update_order_status(a,b,c);end$$;
create or replace function public.secure_admin_manage_order(a uuid,b text,c numeric default null,d text default null,e text default null,f uuid default null,g integer default 1) returns void language plpgsql security definer set search_path=public as $$begin if (b='refund' and not public.has_permission('finance.manage')) or (b='cancel' and not public.has_permission('orders.manage')) or (b='return' and not public.has_permission('warehouse.manage')) or (b in('deposit_received','deposit_returned') and not(public.has_permission('finance.manage') or public.has_permission('warehouse.manage'))) or (b='late_fee' and not(public.has_permission('orders.manage') or public.has_permission('warehouse.manage'))) then raise exception 'Izin operasional diperlukan';end if;perform public.admin_manage_order(a,b,c,d,e,f,g);end$$;
create or replace function public.secure_admin_update_customer(a uuid,b boolean,c boolean,d text default null,e text default null) returns void language plpgsql security definer set search_path=public as $$begin if not public.has_permission('customers.manage') then raise exception 'Izin pelanggan diperlukan';end if;perform public.admin_update_customer(a,b,c,d,e);end$$;
create or replace function public.secure_admin_moderate_rating(a uuid,b boolean,c text default null) returns void language plpgsql security definer set search_path=public as $$begin if not public.has_permission('reviews.manage') then raise exception 'Izin moderasi diperlukan';end if;perform public.admin_moderate_website_rating(a,b,c);end$$;
create or replace function public.secure_admin_generate_reminders() returns integer language plpgsql security definer set search_path=public as $$begin if not public.has_permission('notifications.manage') then raise exception 'Izin notifikasi diperlukan';end if;return public.admin_generate_reminders();end$$;
create or replace function public.secure_admin_mark_notification_sent(a uuid) returns void language plpgsql security definer set search_path=public as $$begin if not public.has_permission('notifications.manage') then raise exception 'Izin notifikasi diperlukan';end if;perform public.admin_mark_notification_sent(a);end$$;
create or replace function public.secure_admin_update_participant_status(a uuid,b text) returns void language plpgsql security definer set search_path=public as $$begin if not public.has_permission('trip_participants.manage') then raise exception 'Izin peserta diperlukan';end if;perform public.admin_update_trip_participant_status(a,b);end$$;
create or replace function public.secure_list_customers() returns table(user_id uuid,email text,full_name text,phone text,city text,is_verified boolean,is_blocked boolean,blocked_reason text,internal_notes text,created_at timestamptz,total_orders bigint,total_spent numeric,cancelled_orders bigint,last_order_at timestamptz) language plpgsql security definer set search_path=public as $$begin if not public.has_permission('customers.view') then raise exception 'Izin pelanggan diperlukan';end if;return query select * from public.list_customer_summaries();end$$;
create or replace function public.secure_list_ratings() returns table(id uuid,user_id uuid,email text,full_name text,score integer,comment text,is_hidden boolean,admin_reply text,created_at timestamptz,updated_at timestamptz) language plpgsql security definer set search_path=public as $$begin if not public.has_permission('reviews.manage') then raise exception 'Izin moderasi diperlukan';end if;return query select * from public.list_admin_website_ratings();end$$;
create or replace function public.secure_list_admin_users() returns table(user_id uuid,email text,full_name text,admin_since timestamptz,created_at timestamptz) language plpgsql security definer set search_path=public as $$begin if not public.has_permission('*') then raise exception 'Izin super admin diperlukan';end if;return query select * from public.list_admin_users();end$$;
create or replace function public.secure_add_admin_by_email(a text,b text default null) returns uuid language plpgsql security definer set search_path=public as $$begin if not public.has_permission('*') then raise exception 'Izin super admin diperlukan';end if;return public.add_admin_by_email(a,b);end$$;
create or replace function public.secure_remove_admin_access(a uuid) returns void language plpgsql security definer set search_path=public as $$begin if not public.has_permission('*') then raise exception 'Izin super admin diperlukan';end if;perform public.remove_admin_access(a);end$$;
create or replace function public.secure_list_staff_users() returns table(user_id uuid,email text,full_name text,role text,created_at timestamptz) language plpgsql security definer set search_path=public,auth as $$begin if not public.has_permission('*') then raise exception 'Izin super admin diperlukan';end if;return query select p.id,u.email::text,p.full_name,p.role,p.created_at from public.profiles p join auth.users u on u.id=p.id where p.role<>'user' order by p.created_at;end$$;
create or replace function public.secure_set_staff_role(a text,b text,c text default null) returns uuid language plpgsql security definer set search_path=public,auth as $$declare v_id uuid;begin if not public.has_permission('*') then raise exception 'Izin super admin diperlukan';end if;if b not in('super_admin','order_admin','catalog_admin','finance_admin','warehouse_staff') then raise exception 'Role tidak valid';end if;select id into v_id from auth.users where lower(email)=lower(trim(a)) limit 1;if v_id is null then raise exception 'Akun belum terdaftar';end if;if b<>'super_admin' and exists(select 1 from public.profiles where id=v_id and role='super_admin') and (select count(*) from public.profiles where role='super_admin')<=1 then raise exception 'Minimal satu Super Admin harus aktif';end if;insert into public.profiles(id,full_name,role,updated_at) values(v_id,nullif(trim(c),''),b,now()) on conflict(id) do update set full_name=coalesce(nullif(trim(c),''),public.profiles.full_name),role=b,updated_at=now();return v_id;end$$;
create or replace function public.secure_remove_staff_role(a uuid) returns void language plpgsql security definer set search_path=public as $$begin if not public.has_permission('*') then raise exception 'Izin super admin diperlukan';end if;if a=auth.uid() then raise exception 'Tidak dapat mencabut role akun sendiri';end if;if exists(select 1 from public.profiles where id=a and role='super_admin') and (select count(*) from public.profiles where role='super_admin')<=1 then raise exception 'Minimal satu Super Admin harus aktif';end if;update public.profiles set role='user',updated_at=now() where id=a;if not found then raise exception 'Petugas tidak ditemukan';end if;end$$;

grant execute on function public.has_permission(text),public.is_admin(),public.get_my_staff_permissions() to authenticated;
grant execute on function public.secure_admin_update_order_status(uuid,text,text),public.secure_admin_manage_order(uuid,text,numeric,text,text,uuid,integer),public.secure_admin_update_customer(uuid,boolean,boolean,text,text),public.secure_admin_moderate_rating(uuid,boolean,text),public.secure_admin_generate_reminders(),public.secure_admin_mark_notification_sent(uuid),public.secure_admin_update_participant_status(uuid,text),public.secure_list_customers(),public.secure_list_ratings(),public.secure_list_admin_users(),public.secure_add_admin_by_email(text,text),public.secure_remove_admin_access(uuid),public.secure_list_staff_users(),public.secure_set_staff_role(text,text,text),public.secure_remove_staff_role(uuid) to authenticated;

-- RLS: hapus policy lama pada tabel sensitif lalu buat aturan berbasis izin.
do $$ declare t text;p record;begin foreach t in array array['profiles','items','item_categories','item_images','item_variants','inventory_units','item_price_tiers','orders','order_items','vouchers','voucher_items','voucher_usages','site_settings','trip_details','trip_participants','payment_transactions','payment_webhook_logs','customer_notifications','order_status_history','order_refunds','order_returns','admin_activity_logs'] loop if to_regclass('public.'||t) is not null then for p in select policyname from pg_policies where schemaname='public' and tablename=t loop execute format('drop policy %I on public.%I',p.policyname,t);end loop;end if;end loop;end$$;
create policy profiles_read on public.profiles for select using(id=auth.uid() or public.has_permission('customers.view') or public.has_permission('*'));
create policy profiles_own_update on public.profiles for update using(id=auth.uid()) with check(id=auth.uid());
create policy items_public_read on public.items for select using(is_active=true or public.has_permission('catalog.manage') or public.has_permission('*'));
create policy items_catalog_write on public.items for all using(public.has_permission('catalog.manage') or public.has_permission('*')) with check(public.has_permission('catalog.manage') or public.has_permission('*'));
create policy orders_read on public.orders for select using(user_id=auth.uid() or public.has_permission('orders.view') or public.has_permission('*'));
create policy order_items_read on public.order_items for select using(exists(select 1 from public.orders o where o.id=order_id and (o.user_id=auth.uid() or public.has_permission('orders.view') or public.has_permission('*'))));
create policy vouchers_staff on public.vouchers for all using(public.has_permission('vouchers.manage') or public.has_permission('*')) with check(public.has_permission('vouchers.manage') or public.has_permission('*'));
create policy settings_read on public.site_settings for select using(true);create policy settings_write on public.site_settings for all using(public.has_permission('settings.manage') or public.has_permission('*')) with check(public.has_permission('settings.manage') or public.has_permission('*'));
create policy audit_super_read on public.admin_activity_logs for select using(public.has_permission('*'));

-- Policies generik untuk tabel katalog dan operasional yang tersedia.
do $$ declare t text;begin foreach t in array array['item_categories','item_images','item_variants','item_price_tiers','trip_details'] loop if to_regclass('public.'||t) is not null then execute format('create policy public_read on public.%I for select using(true)',t);execute format('create policy catalog_write on public.%I for all using(public.has_permission(''catalog.manage'') or public.has_permission(''*'')) with check(public.has_permission(''catalog.manage'') or public.has_permission(''*''))',t);end if;end loop;end$$;
create policy inventory_staff on public.inventory_units for all using(public.has_permission('warehouse.manage') or public.has_permission('catalog.manage') or public.has_permission('*')) with check(public.has_permission('warehouse.manage') or public.has_permission('catalog.manage') or public.has_permission('*'));
create policy participants_read on public.trip_participants for select using(user_id=auth.uid() or public.has_permission('trip_participants.manage') or public.has_permission('*'));
create policy payments_read on public.payment_transactions for select using(exists(select 1 from public.orders o where o.id=order_id and o.user_id=auth.uid()) or public.has_permission('finance.manage') or public.has_permission('*'));
create policy payment_logs_finance on public.payment_webhook_logs for select using(public.has_permission('finance.manage') or public.has_permission('*'));
create policy notifications_read on public.customer_notifications for select using(user_id=auth.uid() or public.has_permission('notifications.manage') or public.has_permission('*'));
create policy history_staff on public.order_status_history for select using(public.has_permission('orders.view') or public.has_permission('*'));
create policy refunds_staff on public.order_refunds for select using(public.has_permission('finance.manage') or public.has_permission('orders.manage') or public.has_permission('*'));
create policy returns_staff on public.order_returns for select using(public.has_permission('warehouse.manage') or public.has_permission('orders.view') or public.has_permission('*'));
create policy voucher_items_staff on public.voucher_items for all using(public.has_permission('vouchers.manage') or public.has_permission('*')) with check(public.has_permission('vouchers.manage') or public.has_permission('*'));
create policy voucher_usages_staff on public.voucher_usages for select using(public.has_permission('vouchers.manage') or public.has_permission('orders.view') or public.has_permission('*'));

drop policy if exists "catalog images admin insert" on storage.objects;drop policy if exists "catalog images admin update" on storage.objects;drop policy if exists "catalog images admin delete" on storage.objects;
drop policy if exists "catalog images catalog insert" on storage.objects;drop policy if exists "catalog images catalog update" on storage.objects;drop policy if exists "catalog images catalog delete" on storage.objects;
create policy "catalog images catalog insert" on storage.objects for insert with check(bucket_id='catalog' and (public.has_permission('catalog.manage') or public.has_permission('*')));
create policy "catalog images catalog update" on storage.objects for update using(bucket_id='catalog' and (public.has_permission('catalog.manage') or public.has_permission('*'))) with check(bucket_id='catalog' and (public.has_permission('catalog.manage') or public.has_permission('*')));
create policy "catalog images catalog delete" on storage.objects for delete using(bucket_id='catalog' and (public.has_permission('catalog.manage') or public.has_permission('*')));

revoke update on public.profiles from authenticated;grant update(full_name,phone,address,city,postal_code) on public.profiles to authenticated;
grant update on public.site_settings to authenticated;
grant select on public.admin_activity_logs to authenticated;
notify pgrst,'reload schema';
