-- AOC V49: pengembalian dimulai dari status DISEWA.
-- Sudah diterapkan ke database AOC; file ini disertakan sebagai dokumentasi/backup patch.
CREATE OR REPLACE FUNCTION public.secure_admin_bulk_return_inspection(p_order_id uuid, p_items jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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
  if v_order.status not in ('paid','rented','returned') then
    raise exception 'Pengembalian hanya dapat diproses pada pesanan Disewa atau Dikembalikan';
  end if;
  select count(*) into v_expected
  from public.order_items oi
  where oi.order_id=p_order_id and oi.item_type='product'
    and (oi.fulfillment_type='rental' or v_order.rental_start is not null)
    and coalesce(oi.returned_quantity,0) < oi.quantity;
  if v_expected=0 then raise exception 'Tidak ada barang yang menunggu pengembalian'; end if;
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
    exception when others then raise exception 'Format checklist pengembalian tidak valid'; end;
    if v_order_item_id is null then raise exception 'Baris barang tidak memiliki order_item_id'; end if;
    if v_condition not in ('good','dirty','damaged','lost') then raise exception 'Kondisi pengembalian tidak valid untuk barang'; end if;
    if v_qty<1 then raise exception 'Jumlah pengembalian harus lebih dari 0'; end if;
    select * into v_line from public.order_items where id=v_order_item_id and order_id=p_order_id and item_type='product' for update;
    if not found then raise exception 'Baris barang tidak ditemukan dalam pesanan'; end if;
    v_remaining := greatest(v_line.quantity-coalesce(v_line.returned_quantity,0),0);
    if v_remaining<1 then raise exception 'Barang % sudah dikembalikan',v_line.title_snapshot; end if;
    if v_qty<>v_remaining then raise exception 'Jumlah kembali untuk % harus % unit',v_line.title_snapshot,v_remaining; end if;
    if v_item_id is not null and v_item_id<>v_line.item_id then raise exception 'Item checklist tidak cocok dengan pesanan'; end if;
    if (select count(*) from jsonb_array_elements(p_items) x where (x->>'order_item_id')=v_entry->>'order_item_id')<>1 then raise exception 'Checklist barang terduplikasi'; end if;
    insert into public.order_returns(order_id,order_item_id,item_id,quantity,condition,fee,notes,inspected_by)
    values(p_order_id,v_order_item_id,v_line.item_id,v_qty,v_condition,v_fee,v_notes,auth.uid());
    update public.order_items set returned_quantity=coalesce(returned_quantity,0)+v_qty where id=v_line.id;
    v_total_fee:=v_total_fee+v_fee; v_conditions:=array_append(v_conditions,v_condition); v_seen:=v_seen+1;
  end loop;
  if exists(select 1 from public.order_items oi where oi.order_id=p_order_id and oi.item_type='product' and coalesce(oi.returned_quantity,0)<oi.quantity) then
    raise exception 'Checklist belum lengkap: masih ada barang yang belum kembali';
  end if;
  update public.orders set status='returned', returned_at=coalesce(returned_at,now()),
    return_condition=case when array_length(v_conditions,1)=1 then v_conditions[1] else 'mixed' end,
    inspection_notes='Checklist seluruh barang disimpan sekaligus oleh admin.',
    late_fee=coalesce(late_fee,0)+v_total_fee where id=p_order_id;
  return jsonb_build_object('order_id',p_order_id,'items_saved',v_seen,'fee_added',v_total_fee,'status','returned');
end;
$function$;
