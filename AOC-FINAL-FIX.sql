-- ============================================================================
-- AOC FINAL FIX V4
-- Location-aware inventory + strict 2-mode separation + safe stock lifecycle
-- Jalankan PALING AKHIR setelah seluruh SQL fitur AOC lainnya.
-- ============================================================================

begin;

-- --------------------------------------------------------------------------
-- 1. Server-side guard: satu order tidak boleh mencampur SALE + RENTAL.
--    Open Trip tetap boleh digabung dengan rental.
-- --------------------------------------------------------------------------
create or replace function public.aoc_guard_mixed_sale_rental()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.order_items oi
    where oi.order_id = new.order_id
      and oi.item_type = 'product'
      and oi.fulfillment_type = 'sale'
  )
  and exists (
    select 1
    from public.order_items oi
    where oi.order_id = new.order_id
      and oi.item_type = 'product'
      and oi.fulfillment_type = 'rental'
  ) then
    raise exception 'Pesanan tidak boleh mencampur mode Jual dan Sewa. Buat dua pesanan terpisah.';
  end if;
  return new;
end;
$$;

drop trigger if exists aoc_guard_mixed_sale_rental_trigger on public.order_items;
create constraint trigger aoc_guard_mixed_sale_rental_trigger
  after insert or update of fulfillment_type on public.order_items
  deferrable initially deferred
  for each row
  execute function public.aoc_guard_mixed_sale_rental();

-- --------------------------------------------------------------------------
-- 2. Ketersediaan RENTAL harus membaca stok toko yang dipilih, bukan total
--    semua toko. Reservation juga sudah dibatasi lokasi oleh peak function.
-- --------------------------------------------------------------------------
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

  select public.aoc_location_stock(p_item_id, null)
    into v_stock;

  if not exists (
    select 1 from public.items i
    where i.id = p_item_id
      and i.type = 'product'
      and i.is_active = true
      and coalesce(i.rental_enabled, true) = true
  ) then
    raise exception 'Item sewa tidak ditemukan atau tidak aktif';
  end if;

  v_reserved := public.rental_peak_reserved_stock_between(
    p_item_id, null, p_start, p_end
  );

  return greatest(coalesce(v_stock,0) - coalesce(v_reserved,0), 0);
end;
$$;

create or replace function public.rental_available_variant_stock(
  p_item_id uuid,
  p_variant_id uuid,
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

  if not exists (
    select 1
    from public.item_variants v
    join public.items i on i.id = v.item_id
    where v.id = p_variant_id
      and v.item_id = p_item_id
      and v.is_active = true
      and i.type = 'product'
      and i.is_active = true
      and coalesce(i.rental_enabled, true) = true
  ) then
    raise exception 'Ukuran atau kapasitas tidak tersedia';
  end if;

  select public.aoc_location_stock(p_item_id, p_variant_id)
    into v_stock;

  v_reserved := public.rental_peak_reserved_stock_between(
    p_item_id, p_variant_id, p_start, p_end
  );

  return greatest(coalesce(v_stock,0) - coalesce(v_reserved,0), 0);
end;
$$;

revoke all on function public.rental_available_stock(uuid,date,date) from public;
revoke all on function public.rental_available_variant_stock(uuid,uuid,date,date) from public;
grant execute on function public.rental_available_stock(uuid,date,date) to anon,authenticated;
grant execute on function public.rental_available_variant_stock(uuid,uuid,date,date) to anon,authenticated;

-- --------------------------------------------------------------------------
-- 3. Ketersediaan JUAL harus membaca stok toko yang dipilih dan mengurangi
--    reservation rental toko yang sama.
-- --------------------------------------------------------------------------
create or replace function public.sale_available_stock(p_item_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stock integer;
  v_peak integer;
begin
  if not exists (
    select 1 from public.items i
    where i.id = p_item_id
      and i.type = 'product'
      and i.is_active = true
      and coalesce(i.sale_enabled,false) = true
  ) then
    raise exception 'Item jual tidak ditemukan atau tidak aktif';
  end if;

  select public.aoc_location_stock(p_item_id, null)
    into v_stock;
  v_peak := public.rental_peak_reserved_stock(p_item_id, null);

  return greatest(coalesce(v_stock,0) - coalesce(v_peak,0), 0);
end;
$$;

create or replace function public.sale_available_variant_stock(
  p_item_id uuid,
  p_variant_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stock integer;
  v_peak integer;
begin
  if not exists (
    select 1
    from public.item_variants v
    join public.items i on i.id = v.item_id
    where v.id = p_variant_id
      and v.item_id = p_item_id
      and v.is_active = true
      and i.type = 'product'
      and i.is_active = true
      and coalesce(i.sale_enabled,false) = true
  ) then
    raise exception 'Varian jual tidak ditemukan atau tidak aktif';
  end if;

  select public.aoc_location_stock(p_item_id, p_variant_id)
    into v_stock;
  v_peak := public.rental_peak_reserved_stock(p_item_id, p_variant_id);

  return greatest(coalesce(v_stock,0) - coalesce(v_peak,0), 0);
end;
$$;

revoke all on function public.sale_available_stock(uuid) from public;
revoke all on function public.sale_available_variant_stock(uuid,uuid) from public;
grant execute on function public.sale_available_stock(uuid) to anon,authenticated;
grant execute on function public.sale_available_variant_stock(uuid,uuid) to anon,authenticated;

-- --------------------------------------------------------------------------
-- 4. SATU trigger stok final.
--    Rental tidak pernah mengurangi physical stock.
--    Sale mengurangi stok lokasi saat PAID dan hanya dikembalikan bila
--    transaksi sale yang sudah PAID dibatalkan.
-- --------------------------------------------------------------------------
create or replace function public.aoc_final_sync_sale_stock()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_line public.order_items%rowtype;
  v_location uuid;
  v_available integer;
begin
  select o.location_id into v_location
  from public.orders o
  where o.id = new.id;

  if v_location is null then
    raise exception 'Lokasi pesanan belum tersedia';
  end if;

  -- PAID -> potong stok SALE tepat satu kali.
  if new.status = 'paid' and old.status <> 'paid' then
    for v_line in
      select *
      from public.order_items
      where order_id = new.id
        and item_type = 'product'
        and fulfillment_type = 'sale'
        and not coalesce(stock_deducted,false)
      for update
    loop
      -- Kunci baris stok lokasi agar dua pembayaran bersamaan tidak bisa
      -- mengurangi stok yang sama.
      if v_line.variant_id is null then
        perform 1
        from public.item_location_stock s
        where s.item_id = v_line.item_id
          and s.variant_id is null
          and s.location_id = v_location
        for update;

        v_available := public.sale_available_stock(v_line.item_id);

        if v_available < v_line.quantity then
          raise exception 'Stok jual % di lokasi pesanan tidak cukup. Tersedia % unit.',
            v_line.title_snapshot, v_available;
        end if;

        update public.item_location_stock
        set stock = stock - v_line.quantity,
            updated_at = now()
        where item_id = v_line.item_id
          and variant_id is null
          and location_id = v_location
          and stock >= v_line.quantity;
      else
        perform 1
        from public.item_location_stock s
        where s.item_id = v_line.item_id
          and s.variant_id = v_line.variant_id
          and s.location_id = v_location
        for update;

        v_available := public.sale_available_variant_stock(v_line.item_id, v_line.variant_id);

        if v_available < v_line.quantity then
          raise exception 'Stok jual % di lokasi pesanan tidak cukup. Tersedia % unit.',
            v_line.title_snapshot, v_available;
        end if;

        update public.item_location_stock
        set stock = stock - v_line.quantity,
            updated_at = now()
        where item_id = v_line.item_id
          and variant_id = v_line.variant_id
          and location_id = v_location
          and stock >= v_line.quantity;
      end if;

      if not found then
        raise exception 'Stok jual % tidak cukup ketika pembayaran dikonfirmasi.',
          v_line.title_snapshot;
      end if;

      update public.order_items
      set stock_deducted = true
      where id = v_line.id;
    end loop;
  end if;

  -- PAID -> CANCELLED: kembalikan hanya stok SALE yang benar-benar dipotong.
  if new.status = 'cancelled' and old.status = 'paid' then
    for v_line in
      select *
      from public.order_items
      where order_id = new.id
        and item_type = 'product'
        and fulfillment_type = 'sale'
        and coalesce(stock_deducted,false)
      for update
    loop
      insert into public.item_location_stock(
        item_id, variant_id, location_id, stock, updated_at
      ) values (
        v_line.item_id, v_line.variant_id, v_location, v_line.quantity, now()
      )
      on conflict(item_id,variant_id,location_id)
      do update set
        stock = public.item_location_stock.stock + excluded.stock,
        updated_at = now();

      update public.order_items
      set stock_deducted = false
      where id = v_line.id;
    end loop;
  end if;

  return new;
end;
$$;

-- Hapus semua trigger stok sale/rental lama yang berpotensi dobel.
drop trigger if exists orders_sync_rental_stock_trigger on public.orders;
drop trigger if exists orders_sync_sale_stock_trigger on public.orders;
drop trigger if exists zzz_aoc_location_sale_stock_trigger on public.orders;

-- PostgreSQL trigger final dibuat satu kali agar tidak ada pemotongan stok ganda.
-- jelas bahwa hanya satu trigger final yang mengelola physical sale stock.
drop trigger if exists aoc_final_sale_stock_trigger on public.orders;
create trigger aoc_final_sale_stock_trigger
after update of status on public.orders
for each row
when (old.status is distinct from new.status)
execute function public.aoc_final_sync_sale_stock();

-- --------------------------------------------------------------------------
-- 5. Sinkronisasi total legacy items.stock / item_variants.stock.
--    Jangan gunakan total legacy sebagai sumber ketersediaan toko.
-- --------------------------------------------------------------------------
create or replace function public.aoc_refresh_legacy_stock(
  p_item_id uuid,
  p_variant_id uuid default null
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_total integer;
begin
  if p_variant_id is null then
    select coalesce(sum(stock),0)::integer
      into v_total
      from public.item_location_stock
     where item_id=p_item_id and variant_id is null;
    update public.items set stock=v_total where id=p_item_id;
  else
    select coalesce(sum(stock),0)::integer
      into v_total
      from public.item_location_stock
     where item_id=p_item_id and variant_id=p_variant_id;
    update public.item_variants set stock=v_total where id=p_variant_id;
  end if;
end;
$$;

-- Pastikan trigger agregasi tetap hanya satu.
drop trigger if exists aoc_refresh_total_location_stock on public.item_location_stock;
create trigger aoc_refresh_total_location_stock
after insert or update or delete on public.item_location_stock
for each row
execute function public.aoc_refresh_total_after_location_stock();

-- --------------------------------------------------------------------------
-- 6. Keamanan fungsi final.
-- --------------------------------------------------------------------------
revoke all on function public.aoc_final_sync_sale_stock() from public;
revoke all on function public.aoc_guard_mixed_sale_rental() from public;
grant execute on function public.aoc_final_sync_sale_stock() to authenticated;

do $$
begin
  if to_regclass('public.item_location_stock') is null then
    raise exception 'item_location_stock belum tersedia. Jalankan MULTI-LOKASI-STOCK.sql terlebih dahulu.';
  end if;
end;
$$;

notify pgrst, 'reload schema';
commit;
