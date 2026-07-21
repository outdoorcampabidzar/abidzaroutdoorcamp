-- Penghapusan permanen pesanan melalui Admin Panel.
-- Hanya dapat dijalankan oleh Super Admin.

create or replace function public.admin_delete_all_cancelled_orders()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted integer := 0;
begin
  if not public.has_permission('*') then
    raise exception 'Hanya Super Admin yang dapat menghapus pesanan permanen';
  end if;

  select count(*)::integer into v_deleted
  from public.orders where status='cancelled';

  if v_deleted = 0 then return 0; end if;

  -- Perlindungan untuk data lama: pulihkan stok jika masih tercatat terpotong.
  update public.items i
  set stock = i.stock + restore.quantity
  from (
    select oi.item_id, sum(oi.quantity)::integer as quantity
    from public.order_items oi
    join public.orders o on o.id=oi.order_id
    where o.status='cancelled'
      and oi.item_type='product'
      and coalesce(oi.stock_deducted,false)
    group by oi.item_id
  ) restore
  where i.id=restore.item_id;

  update public.order_items oi
  set stock_deducted=false
  from public.orders o
  where o.id=oi.order_id and o.status='cancelled' and oi.stock_deducted;

  -- Log webhook tidak memiliki foreign key, sehingga dibersihkan lebih dahulu.
  delete from public.payment_webhook_logs log
  where log.gateway_transaction_id in (
    select pt.gateway_transaction_id
    from public.payment_transactions pt
    join public.orders o on o.id=pt.order_id
    where o.status='cancelled'
  );

  -- Tabel ini memakai ON DELETE RESTRICT.
  delete from public.voucher_usages usage
  using public.orders o
  where usage.order_id=o.id and o.status='cancelled';

  -- Tabel anak lain menggunakan ON DELETE CASCADE.
  delete from public.orders where status='cancelled';

  return v_deleted;
end;
$$;

revoke all on function public.admin_delete_all_cancelled_orders() from public;
grant execute on function public.admin_delete_all_cancelled_orders() to authenticated;

notify pgrst, 'reload schema';

-- Hapus permanen SEMUA pesanan dari seluruh status.
create or replace function public.admin_delete_all_orders()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted integer := 0;
begin
  if not public.has_permission('*') then
    raise exception 'Hanya Super Admin yang dapat menghapus seluruh pesanan';
  end if;

  select count(*)::integer into v_deleted from public.orders;
  if v_deleted = 0 then return 0; end if;

  -- Kembalikan stok item yang masih tercatat terpotong (umumnya status Dibayar).
  update public.items i
  set stock = i.stock + restore.quantity
  from (
    select oi.item_id, sum(oi.quantity)::integer as quantity
    from public.order_items oi
    where oi.item_type='product' and coalesce(oi.stock_deducted,false)
    group by oi.item_id
  ) restore
  where i.id=restore.item_id;

  update public.order_items
  set stock_deducted=false
  where stock_deducted;

  -- Kembalikan kuota open trip yang sebelumnya sudah dipakai status aktif.
  update public.items i
  set quota = coalesce(i.quota,0) + restore.quantity
  from (
    select oi.item_id, sum(oi.quantity)::integer as quantity
    from public.order_items oi
    join public.orders o on o.id=oi.order_id
    where oi.item_type='trip' and o.status in ('confirmed','paid','completed')
    group by oi.item_id
  ) restore
  where i.id=restore.item_id;

  -- Sesuaikan penghitung pemakaian voucher sebelum riwayat dihapus.
  update public.vouchers v
  set used_count = greatest(v.used_count-used.total,0)
  from (
    select voucher_code, count(*)::integer as total
    from public.orders
    where voucher_code is not null
      and status in ('confirmed','paid','completed')
    group by voucher_code
  ) used
  where v.code=used.voucher_code;

  delete from public.payment_webhook_logs log
  where log.gateway_transaction_id in (
    select gateway_transaction_id from public.payment_transactions
  );

  delete from public.voucher_usages;
  delete from public.orders;

  -- Bersihkan jejak audit yang hanya menunjuk data pesanan yang sudah dihapus.
  delete from public.admin_activity_logs
  where table_name in (
    'orders','order_items','order_status_history','order_refunds','order_returns',
    'payment_transactions','payment_webhook_logs','trip_participants'
  );

  return v_deleted;
end;
$$;

revoke all on function public.admin_delete_all_orders() from public;
grant execute on function public.admin_delete_all_orders() to authenticated;

notify pgrst, 'reload schema';
