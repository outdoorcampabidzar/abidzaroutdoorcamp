-- AbidzarOutdoorcamp - Pelanggan, moderasi ulasan, dan notifikasi
-- Jalankan setelah backup.txt, rental-calendar.sql, dan order-management.sql.

alter table public.profiles add column if not exists is_verified boolean not null default false;
alter table public.profiles add column if not exists internal_notes text;
alter table public.profiles add column if not exists is_blocked boolean not null default false;
alter table public.profiles add column if not exists blocked_reason text;
alter table public.profiles add column if not exists blocked_at timestamptz;
alter table public.profiles add column if not exists created_at timestamptz not null default now();
alter table public.profiles add column if not exists updated_at timestamptz not null default now();

alter table public.website_ratings add column if not exists is_hidden boolean not null default false;
alter table public.website_ratings add column if not exists admin_reply text;
alter table public.website_ratings add column if not exists moderated_at timestamptz;
alter table public.website_ratings add column if not exists moderated_by uuid references auth.users(id) on delete set null;

create table if not exists public.customer_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  order_id uuid references public.orders(id) on delete cascade,
  notification_type text not null check (notification_type in ('order_created','payment_paid','payment_expired','order_confirmed','pickup_reminder','return_reminder','late_warning','trip_reminder','cancelled','refund','custom')),
  title text not null,
  message text not null,
  scheduled_for timestamptz not null default now(),
  status text not null default 'pending' check (status in ('pending','sent','cancelled')),
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  unique(order_id, notification_type)
);
create index if not exists customer_notifications_schedule_idx on public.customer_notifications(status, scheduled_for);
alter table public.customer_notifications enable row level security;
drop policy if exists "notifications admin read" on public.customer_notifications;
create policy "notifications admin read" on public.customer_notifications for select using (public.is_admin());
drop policy if exists "notifications own read" on public.customer_notifications;
create policy "notifications own read" on public.customer_notifications for select using (auth.uid()=user_id);
grant select on public.customer_notifications to authenticated;

create or replace function public.prevent_blocked_customer_order()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if exists(select 1 from public.profiles where id=new.user_id and is_blocked=true) then
    raise exception 'Akun Anda diblokir. Hubungi administrator.';
  end if;
  return new;
end; $$;
drop trigger if exists orders_prevent_blocked_customer on public.orders;
create trigger orders_prevent_blocked_customer before insert on public.orders for each row execute function public.prevent_blocked_customer_order();

create or replace function public.list_customer_summaries()
returns table(user_id uuid,email text,full_name text,phone text,city text,is_verified boolean,is_blocked boolean,blocked_reason text,internal_notes text,created_at timestamptz,total_orders bigint,total_spent numeric,cancelled_orders bigint,last_order_at timestamptz)
language plpgsql security definer set search_path=public,auth as $$
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  return query select p.id,u.email::text,p.full_name,p.phone,p.city,p.is_verified,p.is_blocked,p.blocked_reason,p.internal_notes,p.created_at,
    count(o.id),coalesce(sum(o.total) filter(where o.status not in ('cancelled')),0),count(o.id) filter(where o.status='cancelled'),max(o.created_at)
  from public.profiles p join auth.users u on u.id=p.id left join public.orders o on o.user_id=p.id
  where lower(trim(p.role)) <> 'admin'
  group by p.id,u.email,p.full_name,p.phone,p.city,p.is_verified,p.is_blocked,p.blocked_reason,p.internal_notes,p.created_at
  order by coalesce(sum(o.total) filter(where o.status not in ('cancelled')),0) desc;
end; $$;

create or replace function public.admin_update_customer(p_user_id uuid,p_verified boolean,p_blocked boolean,p_notes text default null,p_reason text default null)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  update public.profiles set is_verified=coalesce(p_verified,false),is_blocked=coalesce(p_blocked,false),internal_notes=nullif(trim(p_notes),''),blocked_reason=case when p_blocked then nullif(trim(p_reason),'') else null end,blocked_at=case when p_blocked then coalesce(blocked_at,now()) else null end,updated_at=now() where id=p_user_id;
  if not found then raise exception 'Pelanggan tidak ditemukan'; end if;
end; $$;

create or replace function public.list_admin_website_ratings()
returns table(id uuid,user_id uuid,email text,full_name text,score integer,comment text,is_hidden boolean,admin_reply text,created_at timestamptz,updated_at timestamptz)
language plpgsql security definer set search_path=public,auth as $$
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  return query select wr.id,wr.user_id,u.email::text,p.full_name,wr.score,wr.comment,wr.is_hidden,wr.admin_reply,wr.created_at,wr.updated_at from public.website_ratings wr join auth.users u on u.id=wr.user_id left join public.profiles p on p.id=wr.user_id order by wr.updated_at desc;
end; $$;

create or replace function public.admin_moderate_website_rating(p_rating_id uuid,p_hidden boolean,p_reply text default null)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  update public.website_ratings set is_hidden=coalesce(p_hidden,false),admin_reply=nullif(trim(p_reply),''),moderated_at=now(),moderated_by=auth.uid(),updated_at=now() where id=p_rating_id;
  if not found then raise exception 'Ulasan tidak ditemukan'; end if;
end; $$;

create or replace function public.queue_order_notification()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_type text; v_title text; v_message text;
begin
  if tg_op='INSERT' then v_type:='order_created'; v_title:='Pesanan dibuat'; v_message:='Pesanan '||new.order_number||' berhasil dibuat.';
  elsif old.payment_status is distinct from new.payment_status and new.payment_status='paid' then v_type:='payment_paid';v_title:='Pembayaran berhasil';v_message:='Pembayaran pesanan '||new.order_number||' telah diterima.';
  elsif old.payment_status is distinct from new.payment_status and new.payment_status='expired' then v_type:='payment_expired';v_title:='Pembayaran kedaluwarsa';v_message:='Pembayaran pesanan '||new.order_number||' telah kedaluwarsa.';
  elsif old.status is distinct from new.status and new.status='confirmed' then v_type:='order_confirmed';v_title:='Pesanan dikonfirmasi';v_message:='Pesanan '||new.order_number||' telah dikonfirmasi.';
  elsif old.status is distinct from new.status and new.status='cancelled' then v_type:='cancelled';v_title:='Pesanan dibatalkan';v_message:='Pesanan '||new.order_number||' dibatalkan.';
  elsif old.payment_status is distinct from new.payment_status and new.payment_status='refunded' then v_type:='refund';v_title:='Refund dicatat';v_message:='Refund pesanan '||new.order_number||' telah dicatat.';
  else return new; end if;
  insert into public.customer_notifications(user_id,order_id,notification_type,title,message,scheduled_for) values(new.user_id,new.id,v_type,v_title,v_message,now()) on conflict do nothing;
  return new;
end; $$;
drop trigger if exists orders_customer_notification_trigger on public.orders;
create trigger orders_customer_notification_trigger after insert or update of status,payment_status on public.orders for each row execute function public.queue_order_notification();

create or replace function public.admin_generate_reminders()
returns integer language plpgsql security definer set search_path=public as $$
declare v_count integer:=0; v_rows integer:=0;
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  insert into public.customer_notifications(user_id,order_id,notification_type,title,message,scheduled_for)
  select o.user_id,o.id,'pickup_reminder','Pengingat pengambilan','Pengambilan pesanan '||o.order_number||' dijadwalkan besok.',now() from public.orders o where o.rental_start=current_date+1 and o.status in ('confirmed','paid') on conflict do nothing; get diagnostics v_count=row_count;
  insert into public.customer_notifications(user_id,order_id,notification_type,title,message,scheduled_for)
  select o.user_id,o.id,'return_reminder','Pengingat pengembalian','Pengembalian pesanan '||o.order_number||' dijadwalkan besok.',now() from public.orders o where o.rental_end=current_date+1 and o.status in ('confirmed','paid') on conflict do nothing; get diagnostics v_rows=row_count; v_count:=v_count+v_rows;
  insert into public.customer_notifications(user_id,order_id,notification_type,title,message,scheduled_for)
  select o.user_id,o.id,'late_warning','Peringatan keterlambatan','Pesanan '||o.order_number||' melewati batas pengembalian.',now() from public.orders o where o.rental_end<current_date and o.returned_at is null and o.status in ('confirmed','paid') on conflict do nothing; get diagnostics v_rows=row_count; v_count:=v_count+v_rows;
  insert into public.customer_notifications(user_id,order_id,notification_type,title,message,scheduled_for)
  select distinct o.user_id,o.id,'trip_reminder','Trip segera berangkat','Open trip pada pesanan '||o.order_number||' berangkat dalam 2 hari.',now() from public.orders o join public.order_items oi on oi.order_id=o.id where oi.item_type='trip' and oi.trip_date_snapshot between current_date and current_date+2 and o.status in ('confirmed','paid') on conflict do nothing; get diagnostics v_rows=row_count; v_count:=v_count+v_rows;
  return v_count;
end; $$;

create or replace function public.admin_mark_notification_sent(p_notification_id uuid)
returns void language plpgsql security definer set search_path=public as $$ begin if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if; update public.customer_notifications set status='sent',sent_at=now() where id=p_notification_id; end; $$;

create or replace function public.get_website_rating()
returns jsonb language plpgsql stable security definer set search_path=public,auth as $$
declare v_average numeric:=0;v_count bigint:=0;v_my_score integer:=0;v_my_comment text:='';
begin
  select coalesce(round(avg(score)::numeric,1),0),count(*) into v_average,v_count from public.website_ratings where is_hidden=false;
  if auth.uid() is not null then select score,coalesce(comment,'') into v_my_score,v_my_comment from public.website_ratings where user_id=auth.uid() limit 1; end if;
  return jsonb_build_object('rating_average',v_average,'rating_count',v_count,'my_score',coalesce(v_my_score,0),'my_comment',coalesce(v_my_comment,''));
end; $$;

create or replace function public.get_website_reviews(p_limit integer default 6)
returns table(display_name text,score integer,comment text,created_at timestamptz,updated_at timestamptz,is_mine boolean,total_count bigint)
language sql stable security definer set search_path=public,auth as $$
with visible as (
  select case when nullif(trim(coalesce(p.full_name,'')),'') is not null then split_part(trim(p.full_name),' ',1) else 'Pengguna' end::text,
    wr.score,
    (coalesce(wr.comment,'')||case when nullif(trim(coalesce(wr.admin_reply,'')),'') is not null then E'\n\nBalasan admin: '||wr.admin_reply else '' end)::text,
    wr.created_at,wr.updated_at,(wr.user_id=auth.uid()),count(*) over()
  from public.website_ratings wr left join public.profiles p on p.id=wr.user_id
  where wr.is_hidden=false and nullif(trim(coalesce(wr.comment,'')),'') is not null
  order by case when wr.user_id=auth.uid() then 0 else 1 end,wr.updated_at desc
) select * from visible limit greatest(1,least(coalesce(p_limit,6),30));
$$;

revoke all on function public.list_customer_summaries() from public;
revoke all on function public.admin_update_customer(uuid,boolean,boolean,text,text) from public;
revoke all on function public.list_admin_website_ratings() from public;
revoke all on function public.admin_moderate_website_rating(uuid,boolean,text) from public;
revoke all on function public.admin_generate_reminders() from public;
revoke all on function public.admin_mark_notification_sent(uuid) from public;
grant execute on function public.list_customer_summaries() to authenticated;
grant execute on function public.admin_update_customer(uuid,boolean,boolean,text,text) to authenticated;
grant execute on function public.list_admin_website_ratings() to authenticated;
grant execute on function public.admin_moderate_website_rating(uuid,boolean,text) to authenticated;
grant execute on function public.admin_generate_reminders() to authenticated;
grant execute on function public.admin_mark_notification_sent(uuid) to authenticated;
notify pgrst, 'reload schema';
