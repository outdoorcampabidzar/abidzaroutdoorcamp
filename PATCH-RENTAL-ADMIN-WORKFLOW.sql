-- AOC: Checkout -> Sewa -> Pemeriksaan -> Dikembalikan -> Selesai
-- Jalankan SETELAH order-management.sql, stock-lifecycle.sql, access-security.sql.

-- Finalisasi hanya boleh jika semua unit barang sewa sudah kembali dan setiap item
-- memiliki catatan pemeriksaan kondisi.
create or replace function public.aoc_validate_rental_completion(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_order public.orders%rowtype;
  v_missing integer;
  v_unchecked integer;
begin
  select * into v_order from public.orders where id=p_order_id for update;
  if not found then raise exception 'Pesanan tidak ditemukan'; end if;

  select count(*) into v_missing
  from public.order_items oi
  where oi.order_id=p_order_id
    and oi.item_type='product'
    and (oi.fulfillment_type='rental' or v_order.rental_start is not null)
    and coalesce(oi.returned_quantity,0) < oi.quantity;

  if v_missing > 0 then
    raise exception 'Belum dapat diselesaikan: % item/unit belum dikembalikan', v_missing;
  end if;

  select count(*) into v_unchecked
  from public.order_items oi
  where oi.order_id=p_order_id
    and oi.item_type='product'
    and (oi.fulfillment_type='rental' or v_order.rental_start is not null)
    and not exists (
      select 1 from public.order_returns r
      where r.order_id=p_order_id and r.item_id=oi.item_id
    );

  if v_unchecked > 0 then
    raise exception 'Belum dapat diselesaikan: % barang belum memiliki pemeriksaan kondisi', v_unchecked;
  end if;
end;
$$;

revoke all on function public.aoc_validate_rental_completion(uuid) from public;
grant execute on function public.aoc_validate_rental_completion(uuid) to authenticated;

-- Return dari UI tidak langsung meloncat ke Selesai. Jika seluruh unit sudah kembali,
-- status berhenti di Dikembalikan agar admin melakukan finalisasi setelah checklist.
create or replace function public.secure_admin_manage_order(
  a uuid,b text,c numeric default null,d text default null,e text default null,
  f uuid default null,g integer default 1
) returns void language plpgsql security definer set search_path=public as $$
begin
  if (b='refund' and not public.has_permission('finance.manage'))
     or (b='cancel' and not public.has_permission('orders.manage'))
     or (b='return' and not public.has_permission('warehouse.manage'))
     or (b in('deposit_received','deposit_returned') and not(public.has_permission('finance.manage') or public.has_permission('warehouse.manage')))
     or (b='late_fee' and not(public.has_permission('orders.manage') or public.has_permission('warehouse.manage'))) then
    raise exception 'Izin operasional diperlukan';
  end if;

  perform public.admin_manage_order(a,b,c,d,e,f,g);

  if b='return' then
    -- order-management lama otomatis memberi completed saat semua unit kembali.
    -- Ubah menjadi returned sebagai tahap inspeksi/finalisasi.
    update public.orders set status='returned', returned_at=coalesce(returned_at,now())
    where id=a and status='completed';
  end if;
end;
$$;

-- Selesai harus melalui Dikembalikan + checklist lengkap.
create or replace function public.secure_admin_update_order_status(
  a uuid,b text,c text default null
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_status text;
begin
  if not public.has_permission('orders.manage') then raise exception 'Izin pesanan diperlukan'; end if;
  if b='completed' then
    select status into v_status from public.orders where id=a;
    if v_status is distinct from 'returned' then
      raise exception 'Pesanan harus berstatus Dikembalikan sebelum menjadi Selesai';
    end if;
    perform public.aoc_validate_rental_completion(a);
  end if;
  perform public.admin_update_order_status(a,b,c);
end;
$$;

grant execute on function public.secure_admin_update_order_status(uuid,text,text),
  public.secure_admin_manage_order(uuid,text,numeric,text,text,uuid,integer) to authenticated;

notify pgrst, 'reload schema';
