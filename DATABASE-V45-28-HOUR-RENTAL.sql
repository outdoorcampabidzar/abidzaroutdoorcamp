-- AOC V45: 28-hour rental lifecycle
-- Actual rental clock starts when admin changes a paid rental order to "rented" (Disewa).
-- Each rental day = 28 hours from the actual pickup timestamp.

CREATE OR REPLACE FUNCTION public.aoc_set_rental_due_at()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
declare
  v_days integer;
  v_start timestamptz;
begin
  v_days := greatest(coalesce(new.rental_days, case when new.rental_end is not null and new.rental_start is not null then (new.rental_end-new.rental_start)+1 else 1 end, 1),1);

  v_start := new.rental_start_at;
  if v_start is not null then
    new.rental_due_at := v_start + (v_days * interval '28 hours');
    if new.rental_end_at is null then
      new.rental_end_at := new.rental_due_at;
    end if;
    return new;
  end if;

  if new.rental_start is not null then
    -- Legacy/scheduled orders without an actual pickup timestamp.
    new.rental_due_at := ((new.rental_start::timestamp at time zone 'Asia/Jakarta') + (v_days * interval '28 hours'));
  end if;
  return new;
end;
$$;

DROP TRIGGER IF EXISTS orders_rental_due_at_trigger ON public.orders;
CREATE TRIGGER orders_rental_due_at_trigger
BEFORE INSERT OR UPDATE OF rental_start, rental_end, rental_days, rental_start_at, rental_end_at
ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.aoc_set_rental_due_at();

CREATE OR REPLACE FUNCTION public.aoc_sync_rental_stock_lifecycle()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
begin
  -- Stock/unit is physically taken out only when the admin records the actual pickup.
  if new.status = 'rented' and old.status is distinct from 'rented' then
    if exists (
      select 1 from public.order_items
      where order_id = new.id
        and item_type = 'product'
        and fulfillment_type = 'rental'
    ) then
      perform public.aoc_stage2_allocate_rental_units(new.id);
    end if;
  end if;

  if new.status = 'returned' and old.status is distinct from 'returned' then
    if exists (
      select 1 from public.order_items
      where order_id = new.id
        and item_type = 'product'
        and fulfillment_type = 'rental'
        and coalesce(stock_deducted,false)
    ) then
      perform public.aoc_stage2_restore_rental_stock(new.id,'return');
    end if;
  end if;

  if new.status = 'cancelled' and old.status is distinct from 'cancelled' and old.status in ('paid','rented') then
    if exists (
      select 1 from public.order_items
      where order_id = new.id
        and item_type = 'product'
        and fulfillment_type = 'rental'
        and coalesce(stock_deducted,false)
    ) then
      perform public.aoc_stage2_restore_rental_stock(new.id,'cancel');
    end if;
  end if;

  return new;
end;
$$;

DROP TRIGGER IF EXISTS aoc_rental_stock_lifecycle_trigger ON public.orders;
CREATE TRIGGER aoc_rental_stock_lifecycle_trigger
AFTER UPDATE OF status ON public.orders
FOR EACH ROW
WHEN (new.status IS DISTINCT FROM old.status AND new.status = ANY (ARRAY['rented'::text,'returned'::text,'cancelled'::text]))
EXECUTE FUNCTION public.aoc_sync_rental_stock_lifecycle();

CREATE OR REPLACE FUNCTION public.admin_update_order_status(
  p_order_id uuid,
  p_status text,
  p_admin_notes text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
declare
  v_order public.orders%rowtype;
  v_line public.order_items%rowtype;
  v_old_reserved boolean;
  v_new_reserved boolean;
  v_is_rental boolean;
  v_days integer;
  v_pickup timestamptz;
  v_due timestamptz;
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  if p_status not in ('pending','confirmed','paid','rented','completed','returned','cancelled') then
    raise exception 'Status tidak valid';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'Pesanan tidak ditemukan'; end if;

  select exists(
    select 1 from public.order_items
    where order_id=p_order_id and item_type='product' and fulfillment_type='rental'
  ) into v_is_rental;

  if p_status='rented' then
    if not v_is_rental then raise exception 'Status Disewa hanya untuk pesanan rental'; end if;
    if v_order.status not in ('paid','confirmed') then
      raise exception 'Pesanan rental harus berstatus Dibayar atau Dikonfirmasi sebelum barang diambil';
    end if;

    v_days := greatest(coalesce(v_order.rental_days,1),1);
    v_pickup := now();
    v_due := v_pickup + (v_days * interval '28 hours');

    update public.orders
    set status='rented',
        rental_start_at=v_pickup,
        rental_end_at=v_due,
        rental_due_at=v_due,
        rental_start=(v_pickup at time zone 'Asia/Jakarta')::date,
        rental_end=(v_due at time zone 'Asia/Jakarta')::date,
        admin_notes=nullif(trim(p_admin_notes),'')
    where id=p_order_id;
    return;
  end if;

  v_old_reserved := v_order.status in ('confirmed','paid','rented','completed','returned');
  v_new_reserved := p_status in ('confirmed','paid','rented','completed','returned');

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
        update public.items set quota = coalesce(quota,0) + v_line.quantity where id = v_line.item_id;
      end if;
    end loop;

    if v_order.voucher_code is not null then
      update public.vouchers set used_count = greatest(used_count - 1,0) where code = v_order.voucher_code;
    end if;
  end if;

  update public.orders
  set status = p_status,
      returned_at = case when p_status='returned' then coalesce(returned_at,now()) else returned_at end,
      admin_notes = nullif(trim(p_admin_notes),'')
  where id = p_order_id;
end;
$$;

CREATE OR REPLACE FUNCTION public.secure_admin_update_order_status(a uuid, b text, c text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
begin
  if not public.has_permission('orders.manage') then
    raise exception 'Izin pesanan diperlukan';
  end if;
  if not exists (
    select 1 from public.admin_security_verifications
    where user_id=auth.uid() and verified_until > now()
  ) then
    raise exception 'Verifikasi PIN Admin diperlukan sebelum mengubah status pesanan.';
  end if;
  perform public.admin_update_order_status(a,b,c);
end;
$$;
