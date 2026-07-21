-- Siklus stok otomatis AbidzarOutdoorcamp
-- Jalankan setelah order-management.sql. Jika memakai role bertingkat,
-- jalankan access-security.sql paling akhir.

alter table public.order_items
  add column if not exists stock_deducted boolean not null default false,
  add column if not exists returned_quantity integer not null default 0;

-- price_snapshot menyimpan harga satu unit untuk seluruh periode/paket.
alter table public.order_items
  drop constraint if exists order_items_rental_total_check;
update public.order_items
set price_snapshot = line_total / quantity
where quantity > 0
  and line_total is distinct from price_snapshot * quantity;
alter table public.order_items
  add constraint order_items_rental_total_check
  check (line_total = price_snapshot * quantity);

alter table public.order_items
  drop constraint if exists order_items_returned_quantity_check;
alter table public.order_items
  add constraint order_items_returned_quantity_check
  check (returned_quantity >= 0 and returned_quantity <= quantity);

-- Menambahkan status eksplisit ketika seluruh barang sudah kembali.
alter table public.orders drop constraint if exists orders_status_check;
alter table public.orders add constraint orders_status_check
  check (status in ('pending','confirmed','paid','completed','returned','cancelled'));

create or replace function public.sync_rental_stock_from_order_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_line public.order_items%rowtype;
  v_outstanding integer;
begin
  -- Aturan utama: status Dibayar mengurangi stok tepat satu kali.
  if new.status = 'paid' and old.status <> 'paid' then
    for v_line in
      select * from public.order_items
      where order_id = new.id and item_type = 'product'
      for update
    loop
      if not v_line.stock_deducted then
        update public.items
        set stock = stock - v_line.quantity
        where id = v_line.item_id and stock >= v_line.quantity;

        if not found then
          raise exception 'Stok % tidak cukup. Tersedia lebih sedikit dari jumlah pesanan.',
            v_line.title_snapshot;
        end if;

        update public.order_items
        set stock_deducted = true
        where id = v_line.id;
      end if;
    end loop;
  end if;

  -- Status Selesai mengembalikan stok. Pembatalan setelah Dibayar juga
  -- mengembalikan stok agar jumlah barang tidak hilang.
  if new.status in ('completed','cancelled','returned')
     and old.status = 'paid' then
    for v_line in
      select * from public.order_items
      where order_id = new.id and item_type = 'product' and stock_deducted
      for update
    loop
      v_outstanding := v_line.quantity;
      if v_outstanding > 0 then
        update public.items
        set stock = stock + v_outstanding
        where id = v_line.item_id;
      end if;

      update public.order_items
      set returned_quantity = case
            when new.status in ('completed','returned') then quantity
            else returned_quantity
          end,
          stock_deducted = false
      where id = v_line.id;
    end loop;
  end if;

  return new;
end;
$$;

drop trigger if exists orders_sync_rental_stock_trigger on public.orders;
create trigger orders_sync_rental_stock_trigger
after update of status on public.orders
for each row
when (old.status is distinct from new.status)
execute function public.sync_rental_stock_from_order_status();

-- Ketersediaan tidak menghitung ganda pesanan yang stoknya sudah dipotong.
create or replace function public.rental_available_stock(
  p_item_id uuid,
  p_start date,
  p_end date
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stock integer;
  v_reserved integer;
begin
  if p_start is null or p_end is null or p_end < p_start then
    raise exception 'Rentang tanggal sewa tidak valid';
  end if;

  select stock into v_stock from public.items
  where id=p_item_id and type='product' and is_active=true;
  if not found then raise exception 'Item sewa tidak ditemukan'; end if;

  select coalesce(sum(oi.quantity),0)::integer into v_reserved
  from public.order_items oi
  join public.orders o on o.id=oi.order_id
  where oi.item_id=p_item_id
    and oi.item_type='product'
    and (o.status in ('pending','confirmed') or (o.status='paid' and not oi.stock_deducted))
    and oi.rental_start<=p_end
    and oi.rental_end>=p_start;

  return greatest(v_stock-v_reserved,0);
end;
$$;

revoke all on function public.rental_available_stock(uuid,date,date) from public;
grant execute on function public.rental_available_stock(uuid,date,date) to anon,authenticated;

-- Menyelaraskan pesanan aktif lama ketika file ini pertama kali dipasang.
do $$
declare
  v_line public.order_items%rowtype;
begin
  -- Versi sebelumnya dapat menandai Dikonfirmasi/Selesai sebagai stok terpotong.
  -- Kembalikan dulu agar hanya status Dibayar yang menahan stok.
  for v_line in
    select oi.*
    from public.order_items oi
    join public.orders o on o.id=oi.order_id
    where oi.item_type='product'
      and o.status<>'paid'
      and oi.stock_deducted
    for update of oi
  loop
    update public.items set stock=stock+v_line.quantity where id=v_line.item_id;
    update public.order_items
    set stock_deducted=false,
        returned_quantity=case
          when exists(select 1 from public.orders o where o.id=v_line.order_id and o.status in ('completed','returned'))
          then quantity else returned_quantity end
    where id=v_line.id;
  end loop;

  for v_line in
    select oi.*
    from public.order_items oi
    join public.orders o on o.id=oi.order_id
    where oi.item_type='product'
      and o.status='paid'
      and not oi.stock_deducted
    for update of oi
  loop
    update public.items
    set stock=stock-v_line.quantity
    where id=v_line.item_id and stock>=v_line.quantity;
    if not found then
      raise exception 'Stok % tidak cukup untuk menyelaraskan pesanan aktif lama',
        v_line.title_snapshot;
    end if;
    update public.order_items set stock_deducted=true where id=v_line.id;
  end loop;
end;
$$;

-- Memastikan fungsi status menerima status "returned". Stok produk dikelola trigger
-- di atas, sedangkan kuota open trip tetap menggunakan mekanisme yang sudah ada.
create or replace function public.admin_update_order_status(
  p_order_id uuid, p_status text, p_admin_notes text default null
)
returns void language plpgsql security definer set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_line public.order_items%rowtype;
  v_old_reserved boolean;
  v_new_reserved boolean;
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  if p_status not in ('pending','confirmed','paid','completed','returned','cancelled') then
    raise exception 'Status tidak valid';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'Pesanan tidak ditemukan'; end if;

  v_old_reserved := v_order.status in ('confirmed','paid','completed');
  v_new_reserved := p_status in ('confirmed','paid','completed');

  if not v_old_reserved and v_new_reserved then
    for v_line in select * from public.order_items where order_id = p_order_id loop
      if v_line.item_type = 'trip' then
        update public.items set quota = quota - v_line.quantity
        where id = v_line.item_id and coalesce(quota,0) >= v_line.quantity;
        if not found then raise exception 'Kuota % tidak cukup', v_line.title_snapshot; end if;
      end if;
    end loop;
    if v_order.voucher_code is not null then
      update public.vouchers set used_count = used_count + 1
      where code = v_order.voucher_code and used_count < quota;
      if not found then raise exception 'Kuota voucher habis'; end if;
    end if;
  elsif v_old_reserved and p_status = 'cancelled' then
    for v_line in select * from public.order_items where order_id = p_order_id loop
      if v_line.item_type = 'trip' then
        update public.items set quota = coalesce(quota,0) + v_line.quantity
        where id = v_line.item_id;
      end if;
    end loop;
    if v_order.voucher_code is not null then
      update public.vouchers set used_count = greatest(used_count - 1,0)
      where code = v_order.voucher_code;
    end if;
  end if;

  update public.orders
  set status = p_status,
      returned_at = case when p_status='returned' then coalesce(returned_at,now()) else returned_at end,
      admin_notes = nullif(trim(p_admin_notes),'')
  where id = p_order_id;
end;
$$;

-- Pengembalian dapat dilakukan sebagian. Stok naik tepat sebanyak jumlah kembali.
create or replace function public.admin_manage_order(
  p_order_id uuid,
  p_action text,
  p_amount numeric default null,
  p_reason text default null,
  p_condition text default null,
  p_item_id uuid default null,
  p_quantity integer default 1
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_order public.orders%rowtype;
  v_payment_id uuid;
  v_refunded numeric;
  v_line public.order_items%rowtype;
  v_return integer;
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  select * into v_order from public.orders where id=p_order_id for update;
  if not found then raise exception 'Pesanan tidak ditemukan'; end if;

  if p_action='cancel' then
    if nullif(trim(p_reason),'') is null then raise exception 'Alasan pembatalan wajib diisi'; end if;
    update public.orders set status='cancelled',cancellation_reason=trim(p_reason),cancelled_at=now() where id=p_order_id;
  elsif p_action='refund' then
    if coalesce(p_amount,0)<=0 then raise exception 'Nominal refund harus lebih dari 0'; end if;
    select coalesce(sum(amount),0) into v_refunded from public.order_refunds where order_id=p_order_id and status<>'failed';
    if v_refunded+p_amount>v_order.total then raise exception 'Total refund melebihi nilai pesanan'; end if;
    select id into v_payment_id from public.payment_transactions where order_id=p_order_id order by created_at desc limit 1;
    insert into public.order_refunds(order_id,payment_transaction_id,amount,refund_type,reason,status,created_by)
    values(p_order_id,v_payment_id,p_amount,case when v_refunded+p_amount>=v_order.total then 'full' else 'partial' end,coalesce(nullif(trim(p_reason),''),'Refund admin'),'recorded',auth.uid());
    if v_refunded+p_amount>=v_order.total then update public.orders set payment_status='refunded',status='cancelled' where id=p_order_id; end if;
  elsif p_action='late_fee' then
    update public.orders set late_fee=greatest(coalesce(p_amount,0),0) where id=p_order_id;
  elsif p_action='deposit_received' then
    update public.orders set deposit_amount=greatest(coalesce(p_amount,0),0),deposit_status='received',deposit_received_at=now() where id=p_order_id;
  elsif p_action='deposit_returned' then
    update public.orders set deposit_status='returned',deposit_returned_at=now() where id=p_order_id;
  elsif p_action='return' then
    if p_condition not in ('good','dirty','damaged','lost') then raise exception 'Kondisi pengembalian tidak valid'; end if;
    select * into v_line from public.order_items
      where order_id=p_order_id and item_id=p_item_id and item_type='product'
      for update;
    if not found then raise exception 'Item sewa tidak ditemukan dalam pesanan'; end if;
    if v_order.status <> 'paid' or not v_line.stock_deducted then
      raise exception 'Pengembalian hanya dapat diproses setelah status Dibayar';
    end if;

    v_return := least(greatest(coalesce(p_quantity,1),1), v_line.quantity-v_line.returned_quantity);
    if v_return <= 0 then raise exception 'Seluruh unit item ini sudah dikembalikan'; end if;

    insert into public.order_returns(order_id,item_id,quantity,condition,fee,notes,inspected_by)
    values(p_order_id,p_item_id,v_return,p_condition,greatest(coalesce(p_amount,0),0),nullif(trim(p_reason),''),auth.uid());

    update public.order_items
      set returned_quantity=returned_quantity+v_return,
          stock_deducted=true
      where id=v_line.id;
    update public.orders set returned_at=now(),return_condition=p_condition,
      inspection_notes=nullif(trim(p_reason),''),late_fee=late_fee+greatest(coalesce(p_amount,0),0)
      where id=p_order_id;

    if not exists (
      select 1 from public.order_items
      where order_id=p_order_id and item_type='product' and returned_quantity<quantity
    ) then
      update public.orders set status='completed' where id=p_order_id;
    end if;
  else
    raise exception 'Aksi tidak dikenal';
  end if;
end;
$$;

revoke all on function public.admin_update_order_status(uuid,text,text) from public;
revoke all on function public.admin_manage_order(uuid,text,numeric,text,text,uuid,integer) from public;
grant execute on function public.admin_update_order_status(uuid,text,text) to authenticated;
grant execute on function public.admin_manage_order(uuid,text,numeric,text,text,uuid,integer) to authenticated;

notify pgrst, 'reload schema';
