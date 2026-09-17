-- AOC FINAL: satu tombol untuk menyimpan seluruh checklist pengembalian rental.
-- Jalankan SETELAH order-management.sql, stock-lifecycle.sql, access-security.sql.
-- Aman dijalankan berulang kali.

alter table public.order_returns
  add column if not exists order_item_id uuid references public.order_items(id) on delete set null;

create index if not exists order_returns_order_item_idx
  on public.order_returns(order_item_id, inspected_at desc);

-- Validasi final diperbaiki agar setiap BARIS order_items diperiksa, bukan hanya item_id.
create or replace function public.aoc_validate_rental_completion(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_missing integer;
  v_unchecked integer;
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;

  select count(*) into v_missing
  from public.order_items oi
  join public.orders o on o.id=oi.order_id
  where oi.order_id=p_order_id
    and oi.item_type='product'
    and (oi.fulfillment_type='rental' or o.rental_start is not null)
    and coalesce(oi.returned_quantity,0) < oi.quantity;
  if v_missing>0 then
    raise exception 'Belum dapat diselesaikan: % baris barang belum dikembalikan penuh',v_missing;
  end if;

  select count(*) into v_unchecked
  from public.order_items oi
  join public.orders o on o.id=oi.order_id
  where oi.order_id=p_order_id
    and oi.item_type='product'
    and (oi.fulfillment_type='rental' or o.rental_start is not null)
    and not exists (
      select 1 from public.order_returns r
      where r.order_id=oi.order_id
        and (r.order_item_id=oi.id or (r.order_item_id is null and r.item_id=oi.item_id))
    );
  if v_unchecked>0 then
    raise exception 'Belum dapat diselesaikan: % baris barang belum memiliki pemeriksaan kondisi',v_unchecked;
  end if;
end;
$$;

-- Batch return: seluruh checklist disimpan atomik. Jika satu baris gagal,
-- seluruh perubahan dibatalkan (tidak ada kondisi yang tersimpan separuh).
create or replace function public.secure_admin_bulk_return_inspection(
  p_order_id uuid,
  p_items jsonb
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_order public.orders%rowtype;
  v_line public.order_items%rowtype;
  v_entry jsonb;
  v_seen integer:=0;
  v_expected integer:=0;
  v_item_id uuid;
  v_order_item_id uuid;
  v_qty integer;
  v_remaining integer;
  v_condition text;
  v_notes text;
  v_fee numeric;
  v_total_fee numeric:=0;
  v_conditions text[]:=array[]::text[];
begin
  if not public.has_permission('warehouse.manage') and not public.has_permission('orders.manage') and not public.has_permission('*') then
    raise exception 'Izin pengembalian barang diperlukan';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 then
    raise exception 'Checklist pengembalian kosong';
  end if;

  select * into v_order from public.orders where id=p_order_id for update;
  if not found then raise exception 'Pesanan tidak ditemukan'; end if;
  if v_order.status not in ('paid','returned') then
    raise exception 'Pengembalian hanya dapat diproses pada pesanan Dibayar atau Dikembalikan';
  end if;

  select count(*) into v_expected
  from public.order_items oi
  where oi.order_id=p_order_id
    and oi.item_type='product'
    and (oi.fulfillment_type='rental' or v_order.rental_start is not null)
    and coalesce(oi.returned_quantity,0) < oi.quantity;

  if v_expected=0 then
    raise exception 'Tidak ada barang yang menunggu pengembalian';
  end if;
  if jsonb_array_length(p_items) <> v_expected then
    raise exception 'Checklist belum lengkap: harus memproses % baris barang sekaligus',v_expected;
  end if;

  for v_entry in select value from jsonb_array_elements(p_items) loop
    begin
      v_order_item_id := (v_entry->>'order_item_id')::uuid;
      v_item_id := nullif(v_entry->>'item_id','')::uuid;
      v_qty := (v_entry->>'quantity')::integer;
      v_condition := lower(trim(coalesce(v_entry->>'condition','')));
      v_notes := nullif(trim(coalesce(v_entry->>'notes','')),'');
      v_fee := greatest(coalesce((v_entry->>'fee')::numeric,0),0);
    exception when others then
      raise exception 'Format checklist pengembalian tidak valid';
    end;

    if v_order_item_id is null then raise exception 'Baris barang tidak memiliki order_item_id'; end if;
    if v_condition not in ('good','dirty','damaged','lost') then
      raise exception 'Kondisi pengembalian tidak valid untuk barang';
    end if;
    if v_qty<1 then raise exception 'Jumlah pengembalian harus lebih dari 0'; end if;

    select * into v_line
    from public.order_items
    where id=v_order_item_id and order_id=p_order_id and item_type='product'
    for update;
    if not found then raise exception 'Baris barang tidak ditemukan dalam pesanan'; end if;

    v_remaining := greatest(v_line.quantity-coalesce(v_line.returned_quantity,0),0);
    if v_remaining<1 then raise exception 'Barang % sudah dikembalikan',v_line.title_snapshot; end if;
    if v_qty<>v_remaining then
      raise exception 'Jumlah kembali untuk % harus % unit',v_line.title_snapshot,v_remaining;
    end if;
    if v_item_id is not null and v_item_id<>v_line.item_id then
      raise exception 'Item checklist tidak cocok dengan pesanan';
    end if;

    -- Tidak boleh ada order_item_id ganda di payload.
    if (select count(*) from jsonb_array_elements(p_items) x where (x->>'order_item_id')=v_entry->>'order_item_id')<>1 then
      raise exception 'Checklist barang terduplikasi';
    end if;

    insert into public.order_returns(order_id,order_item_id,item_id,quantity,condition,fee,notes,inspected_by)
    values(p_order_id,v_order_item_id,v_line.item_id,v_qty,v_condition,v_fee,v_notes,auth.uid());

    update public.order_items
    set returned_quantity=returned_quantity+v_qty
    where id=v_line.id;

    v_total_fee:=v_total_fee+v_fee;
    v_conditions:=array_append(v_conditions,v_condition);
    v_seen:=v_seen+1;
  end loop;

  -- Semua baris harus sudah kembali penuh sebelum status berubah.
  if exists(
    select 1 from public.order_items oi
    where oi.order_id=p_order_id and oi.item_type='product' and coalesce(oi.returned_quantity,0)<oi.quantity
  ) then
    raise exception 'Checklist belum lengkap: masih ada barang yang belum kembali';
  end if;

  -- Trigger stock lifecycle mengembalikan stok saat status menjadi returned.
  update public.orders
  set status='returned',
      returned_at=coalesce(returned_at,now()),
      return_condition=case
        when array_length(v_conditions,1)=1 then v_conditions[1]
        else 'mixed'
      end,
      inspection_notes='Checklist seluruh barang disimpan sekaligus oleh admin.',
      late_fee=coalesce(late_fee,0)+v_total_fee
  where id=p_order_id;

  return jsonb_build_object(
    'order_id',p_order_id,
    'items_saved',v_seen,
    'fee_added',v_total_fee,
    'status','returned'
  );
end;
$$;

revoke all on function public.secure_admin_bulk_return_inspection(uuid,jsonb) from public;
grant execute on function public.secure_admin_bulk_return_inspection(uuid,jsonb) to authenticated;
notify pgrst,'reload schema';
