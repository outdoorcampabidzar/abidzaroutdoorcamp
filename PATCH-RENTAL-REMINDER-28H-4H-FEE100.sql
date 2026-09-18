-- AOC - Pengingat rental 28 jam / hari + reminder H-4 jam + denda otomatis 100%
-- Jalankan SETELAH PATCH-BULK-RETURN-INSPECTION.sql / stock-lifecycle.sql.
-- Aman dijalankan berulang kali.
-- Catatan: checkout saat ini menyimpan rental_start/rental_end sebagai DATE.
-- Karena itu jam awal dihitung dari 00:00 Asia/Jakarta, lalu 28 jam x rental_days.

alter table public.orders
  add column if not exists rental_due_at timestamptz,
  add column if not exists late_fee_percent numeric(5,2) not null default 0,
  add column if not exists late_fee_base numeric(14,2) not null default 0,
  add column if not exists late_fee_applied_at timestamptz;

create table if not exists public.rental_reminders (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  reminder_type text not null check (reminder_type in ('4h_before_due','overdue_fee')),
  due_at timestamptz not null,
  triggered_at timestamptz not null default now(),
  customer_notified boolean not null default false,
  created_at timestamptz not null default now(),
  unique(order_id, reminder_type)
);

create index if not exists rental_reminders_order_idx
  on public.rental_reminders(order_id, reminder_type, triggered_at desc);

-- Isi due time untuk order lama yang belum punya due_at.
update public.orders o
set rental_due_at = (
  ((o.rental_start::timestamp at time zone 'Asia/Jakarta')
   + (greatest(coalesce(o.rental_days, (o.rental_end-o.rental_start)+1, 1),1) * interval '28 hours'))
),
    late_fee_percent = case when coalesce(o.late_fee,0) > 0 then 100 else coalesce(o.late_fee_percent,0) end
where o.rental_start is not null
  and o.rental_due_at is null;

-- Semua order rental baru akan memiliki due_at 28 jam x hari rental.
create or replace function public.aoc_set_rental_due_at()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_days integer;
begin
  if new.rental_start is null then
    return new;
  end if;
  v_days := greatest(coalesce(new.rental_days, case when new.rental_end is not null then (new.rental_end-new.rental_start)+1 else 1 end, 1),1);
  new.rental_due_at := ((new.rental_start::timestamp at time zone 'Asia/Jakarta') + (v_days * interval '28 hours'));
  return new;
end;
$$;

drop trigger if exists orders_rental_due_at_trigger on public.orders;
create trigger orders_rental_due_at_trigger
before insert or update of rental_start,rental_end,rental_days on public.orders
for each row execute function public.aoc_set_rental_due_at();

-- Harga dasar denda = seluruh harga baris rental sebelum denda.
create or replace function public.aoc_rental_fee_base(p_order_id uuid)
returns numeric
language sql
stable
security definer
set search_path=public
as $$
  select coalesce(sum(oi.line_total),0)::numeric
  from public.order_items oi
  where oi.order_id=p_order_id
    and oi.item_type='product'
    and (oi.fulfillment_type='rental' or oi.rental_start is not null);
$$;

-- Mesin otomatis. Dipanggil oleh admin dan dapat dijalankan setiap menit via pg_cron.
create or replace function public.aoc_process_rental_reminders()
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_now timestamptz := now();
  v_order public.orders%rowtype;
  v_base numeric;
  v_fee numeric;
  v_4h integer := 0;
  v_overdue integer := 0;
  v_done integer := 0;
begin
  for v_order in
    select o.*
    from public.orders o
    where o.rental_start is not null
      and o.rental_due_at is not null
      and o.status in ('confirmed','paid','returned')
      and o.returned_at is null
      and o.status <> 'cancelled'
    for update skip locked
  loop
    -- Reminder 4 jam sebelum batas.
    if v_now >= v_order.rental_due_at - interval '4 hours'
       and v_now < v_order.rental_due_at
       and not exists (
         select 1 from public.rental_reminders rr
         where rr.order_id=v_order.id and rr.reminder_type='4h_before_due'
       ) then
      insert into public.rental_reminders(order_id,reminder_type,due_at)
      values(v_order.id,'4h_before_due',v_order.rental_due_at);
      v_4h := v_4h + 1;

      if v_order.user_id is not null then
        insert into public.customer_notifications(
          user_id,order_id,notification_type,title,message,scheduled_for
        )
        values(
          v_order.user_id,
          v_order.id,
          'return_reminder',
          'Pengingat pengembalian rental',
          'Pesanan '||v_order.order_number||' akan berakhir 4 jam lagi. Mohon segera mengembalikan seluruh barang rental.',
          v_now
        ) on conflict do nothing;
      end if;
    end if;

    -- Begitu lewat batas: denda otomatis satu kali = 100% dari seluruh harga sewa.
    if v_now >= v_order.rental_due_at
       and not exists (
         select 1 from public.rental_reminders rr
         where rr.order_id=v_order.id and rr.reminder_type='overdue_fee'
       ) then
      v_base := public.aoc_rental_fee_base(v_order.id);
      v_fee := round(greatest(v_base,0) * 1.00, 2);

      update public.orders
      set late_fee = greatest(coalesce(late_fee,0), v_fee),
          late_fee_percent = 100,
          late_fee_base = greatest(v_base,0),
          late_fee_applied_at = v_now
      where id=v_order.id;

      insert into public.rental_reminders(order_id,reminder_type,due_at)
      values(v_order.id,'overdue_fee',v_order.rental_due_at);
      v_overdue := v_overdue + 1;

      if v_order.user_id is not null then
        insert into public.customer_notifications(
          user_id,order_id,notification_type,title,message,scheduled_for
        )
        values(
          v_order.user_id,
          v_order.id,
          'late_warning',
          'Denda keterlambatan rental',
          'Pesanan '||v_order.order_number||' telah melewati batas pengembalian. Denda otomatis 100% dari seluruh harga sewa: Rp'||to_char(v_fee,'FM999G999G999G999D00'),
          v_now
        ) on conflict do nothing;
      end if;
    end if;
  end loop;

  select count(*) into v_done
  from public.rental_reminders
  where triggered_at >= v_now - interval '1 minute';

  return jsonb_build_object(
    'processed_4h',v_4h,
    'processed_overdue',v_overdue,
    'recent_reminders',v_done,
    'processed_at',v_now
  );
end;
$$;

-- Endpoint admin untuk menjalankan mesin dari panel tanpa membuka akses tabel.
create or replace function public.admin_process_rental_reminders()
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  return public.aoc_process_rental_reminders();
end;
$$;

-- Daftar reminder operasional untuk Admin Panel.
create or replace function public.admin_list_rental_reminders()
returns table(
  id uuid,
  order_id uuid,
  order_number text,
  customer_name text,
  phone text,
  rental_start date,
  rental_end date,
  rental_days integer,
  rental_due_at timestamptz,
  status text,
  subtotal numeric,
  total numeric,
  late_fee numeric,
  late_fee_base numeric,
  late_fee_percent numeric,
  reminder_type text,
  triggered_at timestamptz
)
language plpgsql
security definer
set search_path=public
as $$
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  return query
  select o.id,o.id,o.order_number,o.customer_name,o.phone,o.rental_start,o.rental_end,o.rental_days,
         o.rental_due_at,o.status,o.subtotal,o.total,o.late_fee,o.late_fee_base,o.late_fee_percent,
         rr.reminder_type,rr.triggered_at
  from public.orders o
  join public.rental_reminders rr on rr.order_id=o.id
  order by rr.triggered_at desc;
end;
$$;

revoke all on function public.aoc_set_rental_due_at() from public;
revoke all on function public.aoc_rental_fee_base(uuid) from public;
revoke all on function public.aoc_process_rental_reminders() from public;
revoke all on function public.admin_process_rental_reminders() from public;
revoke all on function public.admin_list_rental_reminders() from public;
grant execute on function public.admin_process_rental_reminders() to authenticated;
grant execute on function public.admin_list_rental_reminders() to authenticated;

-- OPSIONAL tetapi direkomendasikan: jalankan otomatis setiap menit jika pg_cron sudah aktif.
-- Jika project Supabase belum mengaktifkan pg_cron, jalankan 2 baris berikut setelah
-- extension pg_cron diaktifkan dari Dashboard > Database > Extensions.
-- select cron.schedule('aoc-rental-reminder-every-minute','* * * * *', $$select public.aoc_process_rental_reminders();$$);
-- Untuk mengganti job lama: select cron.unschedule('aoc-rental-reminder-every-minute'); lalu schedule ulang.

notify pgrst, 'reload schema';
