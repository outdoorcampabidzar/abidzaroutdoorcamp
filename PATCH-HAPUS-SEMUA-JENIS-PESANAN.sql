-- AOC - HAPUS SATU PESANAN (SEMUA JENIS & SEMUA STATUS)
-- Jalankan SEKALI di Supabase SQL Editor.
-- Hanya Super Admin (permission '*') yang dapat menjalankan.
-- Menghapus satu order beserta data anak yang terkait.
-- Stok/kuota yang masih ditandai terpotong akan dikembalikan tepat satu kali.

create or replace function public.admin_delete_order(
  p_order_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_deleted integer := 0;
  v_voucher_id uuid;
  v_voucher_code text;
  v_voucher_status text;
  v_gateway_ids text[];
begin
  if not public.has_permission('*') then
    raise exception 'Hanya Super Admin yang dapat menghapus pesanan permanen.';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Pesanan tidak ditemukan.';
  end if;

  -- Simpan data voucher sebelum data anak dihapus.
  select vu.voucher_id, vu.voucher_code, vu.status
    into v_voucher_id, v_voucher_code, v_voucher_status
  from public.voucher_usages vu
  where vu.order_id = p_order_id
  limit 1;

  -- Simpan ID transaksi gateway karena webhook log tidak memiliki FK order.
  select coalesce(
    array_agg(pt.gateway_transaction_id) filter (where pt.gateway_transaction_id is not null),
    '{}'::text[]
  )
  into v_gateway_ids
  from public.payment_transactions pt
  where pt.order_id = p_order_id;

  -- Kembalikan stok produk yang masih ditandai stock_deducted.
  -- Setelah ini flag diubah false agar tidak terjadi pengembalian dua kali.
  update public.item_variants v
  set stock = v.stock + restore.quantity
  from (
    select oi.variant_id, sum(oi.quantity)::integer as quantity
    from public.order_items oi
    where oi.order_id = p_order_id
      and oi.item_type = 'product'
      and oi.variant_id is not null
      and coalesce(oi.stock_deducted, false)
    group by oi.variant_id
  ) restore
  where v.id = restore.variant_id;

  update public.items i
  set stock = i.stock + restore.quantity
  from (
    select oi.item_id, sum(oi.quantity)::integer as quantity
    from public.order_items oi
    where oi.order_id = p_order_id
      and oi.item_type = 'product'
      and oi.variant_id is null
      and coalesce(oi.stock_deducted, false)
    group by oi.item_id
  ) restore
  where i.id = restore.item_id;

  update public.order_items
  set stock_deducted = false
  where order_id = p_order_id and stock_deducted;

  -- Kembalikan kuota open trip hanya jika order masih tercatat sebagai pemakai kuota.
  update public.items i
  set quota = coalesce(i.quota, 0) + restore.quantity
  from (
    select oi.item_id, sum(oi.quantity)::integer as quantity
    from public.order_items oi
    where oi.order_id = p_order_id
      and oi.item_type = 'trip'
      and exists (
        select 1 from public.orders o
        where o.id = p_order_id
          and o.status in ('confirmed','paid','completed')
      )
    group by oi.item_id
  ) restore
  where i.id = restore.item_id;

  -- voucher_usages memakai ON DELETE RESTRICT, jadi hapus dulu.
  delete from public.voucher_usages
  where order_id = p_order_id;

  -- Bersihkan webhook log yang tidak memiliki FK ke orders.
  if coalesce(array_length(v_gateway_ids, 1), 0) > 0 then
    delete from public.payment_webhook_logs
    where gateway_transaction_id = any(v_gateway_ids);
  end if;

  -- Data anak lain yang memiliki ON DELETE CASCADE akan ikut terhapus.
  delete from public.orders
  where id = p_order_id;

  if not found then
    raise exception 'Gagal menghapus pesanan.';
  end if;

  -- Counter voucher dikembalikan hanya untuk penggunaan yang benar-benar used.
  if v_voucher_id is not null and coalesce(v_voucher_status, 'used') = 'used' then
    update public.vouchers
    set used_count = greatest(coalesce(used_count, 0) - 1, 0)
    where id = v_voucher_id;
  elsif v_voucher_code is not null and coalesce(v_voucher_status, 'used') = 'used' then
    update public.vouchers
    set used_count = greatest(coalesce(used_count, 0) - 1, 0)
    where code = v_voucher_code;
  end if;

  return jsonb_build_object(
    'success', true,
    'order_id', p_order_id,
    'order_number', v_order.order_number,
    'status', v_order.status,
    'message', 'Pesanan berhasil dihapus permanen.'
  );
end;
$$;

revoke all on function public.admin_delete_order(uuid) from public, anon;
grant execute on function public.admin_delete_order(uuid) to authenticated;

-- Kompatibilitas: tombol lama untuk rental sekarang juga dapat menghapus semua status.
create or replace function public.admin_delete_rental_order(
  p_order_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.admin_delete_order(p_order_id);
end;
$$;

revoke all on function public.admin_delete_rental_order(uuid) from public, anon;
grant execute on function public.admin_delete_rental_order(uuid) to authenticated;

notify pgrst, 'reload schema';
