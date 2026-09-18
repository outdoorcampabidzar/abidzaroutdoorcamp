-- ============================================================================
-- AOC ULTIMATE FINAL
-- Fondasi final: 2-mode, multi-toko, stok aman, return/inspection,
-- finalisasi idempotent, denda 100%, audit, inventory unit, dashboard.
-- Jalankan PALING AKHIR setelah seluruh SQL fitur AOC lainnya.
-- ============================================================================
begin;

-- 1. Kolom finalisasi + denda
alter table public.orders
  add column if not exists late_fee_percent numeric(5,2) not null default 100,
  add column if not exists late_fee_base numeric(14,2) not null default 0,
  add column if not exists finalized_at timestamptz,
  add column if not exists finalized_by uuid references auth.users(id) on delete set null,
  add column if not exists finalization_locked boolean not null default false;

update public.orders set late_fee_percent=100 where late_fee_percent is null or late_fee_percent<>100;

-- 2. Return dapat menunjuk unit fisik tertentu.
alter table public.order_returns
  add column if not exists unit_id uuid references public.inventory_units(id) on delete set null;
create index if not exists order_returns_unit_idx on public.order_returns(unit_id, inspected_at desc);

-- 3. Inventory unit mendukung lokasi toko.
alter table public.inventory_units
  add column if not exists location_id uuid references public.aoc_locations(id) on delete set null;
create index if not exists inventory_units_location_idx on public.inventory_units(location_id, item_id, variant_id, status);

-- 4. Audit finalisasi terpisah dari histori status.
create table if not exists public.rental_finalization_audit (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders(id) on delete cascade,
  finalized_by uuid references auth.users(id) on delete set null,
  finalized_at timestamptz not null default now(),
  late_fee_percent numeric(5,2) not null default 100,
  late_fee_base numeric(14,2) not null default 0,
  late_fee numeric(14,2) not null default 0,
  notes text
);
alter table public.rental_finalization_audit enable row level security;
drop policy if exists "rental finalization admin read" on public.rental_finalization_audit;
create policy "rental finalization admin read" on public.rental_finalization_audit
for select to authenticated using (public.is_admin());
grant select on public.rental_finalization_audit to authenticated;

-- 5. Dasar denda = total harga sewa sebelum denda. Voucher tidak dipakai.
create or replace function public.aoc_rental_late_fee_base(p_order_id uuid)
returns numeric
language sql stable security definer set search_path=public
as $$
  select coalesce(sum(oi.line_total),0)::numeric
  from public.order_items oi
  where oi.order_id=p_order_id
    and oi.item_type='product'
    and oi.fulfillment_type='rental';
$$;

create or replace function public.aoc_calculate_late_fee_100(p_order_id uuid)
returns numeric
language plpgsql security definer set search_path=public
as $$
declare
  v_base numeric;
  v_fee numeric;
  v_status text;
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  select status into v_status from public.orders where id=p_order_id for update;
  if not found then raise exception 'Pesanan tidak ditemukan'; end if;
  v_base:=public.aoc_rental_late_fee_base(p_order_id);
  v_fee:=round(v_base*1.00,2);
  update public.orders
  set late_fee_base=v_base, late_fee_percent=100, late_fee=v_fee
  where id=p_order_id;
  return v_fee;
end;
$$;
revoke all on function public.aoc_rental_late_fee_base(uuid) from public;
grant execute on function public.aoc_rental_late_fee_base(uuid) to anon,authenticated;
revoke all on function public.aoc_calculate_late_fee_100(uuid) from public;
grant execute on function public.aoc_calculate_late_fee_100(uuid) to authenticated;

-- 6. Finalisasi rental: atomik, idempotent, tanpa voucher.
-- Return type/function signature lama pernah berbeda (void vs jsonb).
-- PostgreSQL tidak mengizinkan CREATE OR REPLACE mengubah return type,
-- jadi hapus signature lama terlebih dahulu agar instalasi/upgrade aman.
drop function if exists public.secure_admin_finalize_rental(uuid,text);

create or replace function public.secure_admin_finalize_rental(
  p_order_id uuid,
  p_admin_notes text default null
) returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  v_order public.orders%rowtype;
  v_fee numeric;
  v_base numeric;
begin
  if not public.has_permission('orders.manage') then
    raise exception 'Izin pesanan diperlukan';
  end if;

  select * into v_order from public.orders where id=p_order_id for update;
  if not found then raise exception 'Pesanan tidak ditemukan'; end if;

  -- Aman bila tombol ditekan dua kali: hasil kedua hanya membaca audit final.
  if v_order.status='completed' and v_order.finalization_locked then
    return jsonb_build_object('order_id',p_order_id,'status','completed','already_finalized',true);
  end if;

  if v_order.status<>'returned' then
    raise exception 'Pesanan harus berstatus Dikembalikan sebelum menjadi Selesai';
  end if;
  perform public.aoc_validate_rental_completion(p_order_id);

  v_base:=public.aoc_rental_late_fee_base(p_order_id);
  v_fee:=round(v_base*1.00,2);

  update public.orders
  set status='completed',
      late_fee_base=v_base,
      late_fee_percent=100,
      late_fee=v_fee,
      finalized_at=now(),
      finalized_by=auth.uid(),
      finalization_locked=true,
      admin_notes=coalesce(nullif(trim(p_admin_notes),''),admin_notes)
  where id=p_order_id;

  insert into public.rental_finalization_audit(order_id,finalized_by,late_fee_percent,late_fee_base,late_fee,notes)
  values(p_order_id,auth.uid(),100,v_base,v_fee,nullif(trim(p_admin_notes),''))
  on conflict(order_id) do update set
    finalized_by=excluded.finalized_by,
    finalized_at=excluded.finalized_at,
    late_fee_percent=100,
    late_fee_base=excluded.late_fee_base,
    late_fee=excluded.late_fee,
    notes=excluded.notes;

  -- Tidak membaca atau mengubah voucher.
  return jsonb_build_object('order_id',p_order_id,'status','completed','late_fee',v_fee,'late_fee_base',v_base,'already_finalized',false);
end;
$$;
revoke all on function public.secure_admin_finalize_rental(uuid,text) from public;
grant execute on function public.secure_admin_finalize_rental(uuid,text) to authenticated;

-- 7. Mencegah order selesai diubah kembali ke status operasional.
create or replace function public.aoc_guard_finalized_order()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if old.finalization_locked and new.status is distinct from old.status then
    raise exception 'Pesanan yang sudah selesai dan dikunci tidak dapat diubah statusnya';
  end if;
  if old.finalization_locked and (new.finalization_locked is distinct from old.finalization_locked) then
    raise exception 'Finalisasi pesanan terkunci';
  end if;
  return new;
end;
$$;
drop trigger if exists aoc_guard_finalized_order_trigger on public.orders;
create trigger aoc_guard_finalized_order_trigger
before update on public.orders for each row execute function public.aoc_guard_finalized_order();

-- 8. Dashboard operasional admin, sumber data server-side.
create or replace function public.aoc_admin_dashboard()
returns jsonb
language plpgsql security definer set search_path=public as $$
declare r jsonb;
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  select jsonb_build_object(
    'orders_total', (select count(*) from public.orders),
    'rental_active', (select count(*) from public.orders o where o.status in ('confirmed','paid') and exists(select 1 from public.order_items oi where oi.order_id=o.id and oi.fulfillment_type='rental')),
    'rental_returned', (select count(*) from public.orders o where o.status='returned'),
    'rental_completed', (select count(*) from public.orders o where o.status='completed' and exists(select 1 from public.order_items oi where oi.order_id=o.id and oi.fulfillment_type='rental')),
    'cancelled', (select count(*) from public.orders where status='cancelled'),
    'late_fee_total', (select coalesce(sum(late_fee),0) from public.orders),
    'damaged_returns', (select count(*) from public.order_returns where condition='damaged'),
    'lost_returns', (select count(*) from public.order_returns where condition='lost'),
    'available_units', (select count(*) from public.inventory_units where status='available'),
    'maintenance_units', (select count(*) from public.inventory_units where status='maintenance'),
    'damaged_units', (select count(*) from public.inventory_units where status='damaged')
  ) into r;
  return r;
end;
$$;
revoke all on function public.aoc_admin_dashboard() from public;
grant execute on function public.aoc_admin_dashboard() to authenticated;

-- 9. RPC stok fisik unit: hanya admin, mencegah status invalid.
create or replace function public.aoc_set_inventory_unit_status(
  p_unit_id uuid, p_status text, p_condition text default null, p_notes text default null
) returns void
language plpgsql security definer set search_path=public as $$
begin
  if not public.has_permission('warehouse.manage') and not public.has_permission('orders.manage') and not public.has_permission('*') then
    raise exception 'Izin inventaris diperlukan';
  end if;
  if p_status not in ('available','rented','damaged','maintenance','retired') then raise exception 'Status unit tidak valid'; end if;
  if p_condition is not null and p_condition not in ('new','good','fair','damaged') then raise exception 'Kondisi unit tidak valid'; end if;
  update public.inventory_units
  set status=p_status,
      condition=coalesce(p_condition,condition),
      notes=coalesce(p_notes,notes),
      updated_at=now()
  where id=p_unit_id;
  if not found then raise exception 'Unit inventaris tidak ditemukan'; end if;
end;
$$;
revoke all on function public.aoc_set_inventory_unit_status(uuid,text,text,text) from public;
grant execute on function public.aoc_set_inventory_unit_status(uuid,text,text,text) to authenticated;

-- 10. Audit status: pastikan histori finalisasi tercatat.
insert into public.rental_finalization_audit(order_id,finalized_by,finalized_at,late_fee_percent,late_fee_base,late_fee,notes)
select o.id,o.finalized_by,coalesce(o.finalized_at,now()),100,coalesce(o.late_fee_base,public.aoc_rental_late_fee_base(o.id)),coalesce(o.late_fee,0),'Migrasi finalisasi lama'
from public.orders o
where o.status='completed'
  and exists(select 1 from public.order_items oi where oi.order_id=o.id and oi.fulfillment_type='rental')
on conflict(order_id) do nothing;

update public.orders o
set finalization_locked=true,
    finalized_at=coalesce(o.finalized_at,now()),
    late_fee_percent=100,
    late_fee_base=coalesce(nullif(o.late_fee_base,0),public.aoc_rental_late_fee_base(o.id))
where o.status='completed'
  and exists(select 1 from public.order_items oi where oi.order_id=o.id and oi.fulfillment_type='rental');

notify pgrst,'reload schema';
commit;
