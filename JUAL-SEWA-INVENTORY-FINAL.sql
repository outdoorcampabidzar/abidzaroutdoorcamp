-- ============================================================================
-- ABIDZAROUTDOORCAMP - JUAL + SEWA INVENTORY V3
--
-- Konsep:
--   1. items.stock = stok fisik yang tersisa.
--   2. SALE  -> stok fisik berkurang permanen ketika order menjadi PAID.
--   3. RENTAL -> stok fisik TIDAK berkurang. Ketersediaan dihitung berdasarkan
--                reservation tanggal yang bentrok.
--   4. RETURN RENTAL -> tidak pernah menambah items.stock/item_variants.stock.
--   5. order_items.fulfillment_type membedakan sale/rental/trip.
--   6. Penjualan dibatasi oleh peak rental reservation agar stok yang sudah
--      dijanjikan untuk rental tidak dapat terjual.
--
-- Jalankan SETELAH seluruh SQL lama selesai, terutama:
--   sql/BACKUP-SELURUH-DATABASE.sql
--   order-management.sql
--   rental-calendar.sql
--   JUAL-SEWA-INVENTORY-FINAL.sql
--   btzpay-payment.sql
-- ============================================================================

begin;

-- --------------------------------------------------------------------------
-- 1. Kolom mode jual/sewa
-- --------------------------------------------------------------------------
alter table public.items
  add column if not exists sale_enabled boolean not null default false,
  add column if not exists rental_enabled boolean not null default true,
  add column if not exists sale_price numeric(14,2) not null default 0;

alter table public.orders
  add column if not exists pending_expires_at timestamptz;

create index if not exists orders_pending_expiry_idx
  on public.orders(status, pending_expires_at)
  where status = 'pending';

alter table public.items
  drop constraint if exists items_sale_price_check;
alter table public.items
  add constraint items_sale_price_check check (sale_price >= 0);

-- --------------------------------------------------------------------------
-- 2. Penanda tegas pada setiap order item
-- --------------------------------------------------------------------------
alter table public.order_items
  add column if not exists fulfillment_type text;

-- Data lama tidak memiliki penanda. Produk lama dianggap rental agar tidak
-- tiba-tiba mengurangi stok pada perubahan status berikutnya.
update public.order_items
set fulfillment_type = case
  when item_type = 'trip' then 'trip'
  else 'rental'
end
where fulfillment_type is null;

alter table public.order_items
  alter column fulfillment_type set default 'rental';

alter table public.order_items
  drop constraint if exists order_items_fulfillment_type_check;
alter table public.order_items
  add constraint order_items_fulfillment_type_check
  check (fulfillment_type in ('sale','rental','trip'));

create index if not exists order_items_fulfillment_type_idx
  on public.order_items(fulfillment_type, item_id);

create index if not exists order_items_rental_availability_idx
  on public.order_items(item_id, variant_id, rental_start, rental_end, order_id)
  where item_type='product' and fulfillment_type='rental';

-- --------------------------------------------------------------------------
-- 3. Fungsi menghitung peak rental commitment
-- --------------------------------------------------------------------------
create or replace function public.rental_peak_reserved_stock(
  p_item_id uuid,
  p_variant_id uuid default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_peak integer := 0;
  v_current integer := 0;
begin
  with events as (
    select oi.rental_start as day, sum(oi.quantity)::integer as delta
    from public.order_items oi
    join public.orders o on o.id = oi.order_id
    where oi.item_id = p_item_id
      and oi.item_type = 'product'
      and oi.fulfillment_type = 'rental'
      and oi.rental_start is not null
      and oi.rental_end is not null
      and oi.rental_end >= current_date
      and o.status in ('pending','confirmed','paid')
      and (o.status <> 'pending' or o.created_at >= now() - interval '30 minutes')
      and (
        (p_variant_id is null and oi.variant_id is null)
        or oi.variant_id = p_variant_id
      )
    group by oi.rental_start

    union all

    select (oi.rental_end + 1) as day, (-sum(oi.quantity))::integer as delta
    from public.order_items oi
    join public.orders o on o.id = oi.order_id
    where oi.item_id = p_item_id
      and oi.item_type = 'product'
      and oi.fulfillment_type = 'rental'
      and oi.rental_start is not null
      and oi.rental_end is not null
      and oi.rental_end >= current_date
      and o.status in ('pending','confirmed','paid')
      and (
        (p_variant_id is null and oi.variant_id is null)
        or oi.variant_id = p_variant_id
      )
    group by oi.rental_end + 1
  ),
  day_events as (
    select day, sum(delta)::integer as delta
    from events
    group by day
  ),
  timeline as (
    select day,
           sum(delta) over (order by day rows between unbounded preceding and current row)::integer as running
    from day_events
  )
  select coalesce(max(running),0) into v_peak from timeline;

  return greatest(v_peak,0);
end;
$$;

revoke all on function public.rental_peak_reserved_stock(uuid,uuid) from public;
grant execute on function public.rental_peak_reserved_stock(uuid,uuid) to anon, authenticated;

-- --------------------------------------------------------------------------
-- 4. Peak reservation dalam rentang tanggal tertentu.
--    Berbeda dari SUM biasa: hanya overlap simultan yang mengurangi stok.
-- --------------------------------------------------------------------------
create or replace function public.rental_peak_reserved_stock_between(
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
  v_peak integer := 0;
begin
  if p_start is null or p_end is null or p_end < p_start then
    raise exception 'Rentang tanggal sewa tidak valid';
  end if;

  with reservations as (
    select
      greatest(oi.rental_start, p_start) as start_day,
      least(oi.rental_end, p_end) as end_day,
      oi.quantity
    from public.order_items oi
    join public.orders o on o.id = oi.order_id
    where oi.item_id = p_item_id
      and oi.item_type = 'product'
      and oi.fulfillment_type = 'rental'
      and oi.rental_start is not null
      and oi.rental_end is not null
      and oi.rental_start <= p_end
      and oi.rental_end >= p_start
      and o.status in ('pending','confirmed','paid')
      and (
        (o.status <> 'pending')
        or coalesce(o.pending_expires_at, o.created_at + interval '30 minutes') > now()
      )
      and (
        (p_variant_id is null and oi.variant_id is null)
        or oi.variant_id = p_variant_id
      )
  ),
  events as (
    select start_day as day, sum(quantity)::integer as delta
    from reservations
    group by start_day
    union all
    select end_day + 1 as day, (-sum(quantity))::integer as delta
    from reservations
    group by end_day + 1
  ),
  timeline as (
    select day,
           sum(delta) over (order by day rows between unbounded preceding and current row)::integer as running
    from (
      select day, sum(delta)::integer as delta
      from events
      group by day
    ) e
  )
  select coalesce(max(running),0) into v_peak from timeline;

  return greatest(v_peak,0);
end;
$$;

revoke all on function public.rental_peak_reserved_stock_between(uuid,uuid,date,date) from public;
grant execute on function public.rental_peak_reserved_stock_between(uuid,uuid,date,date) to anon, authenticated;

-- --------------------------------------------------------------------------
-- 4. Ketersediaan rental berdasarkan tanggal
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

  select stock into v_stock
  from public.items
  where id = p_item_id
    and type = 'product'
    and is_active = true
    and coalesce(rental_enabled,true) = true;

  if not found then
    raise exception 'Item sewa tidak ditemukan atau tidak aktif';
  end if;

  v_reserved := public.rental_peak_reserved_stock_between(p_item_id,null,p_start,p_end);
  return greatest(v_stock - v_reserved,0);
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

  select v.stock into v_stock
  from public.item_variants v
  join public.items i on i.id = v.item_id
  where v.id = p_variant_id
    and v.item_id = p_item_id
    and v.is_active = true
    and i.type = 'product'
    and i.is_active = true
    and coalesce(i.rental_enabled,true) = true;

  if not found then
    raise exception 'Ukuran atau kapasitas tidak tersedia';
  end if;

  v_reserved := public.rental_peak_reserved_stock_between(p_item_id,p_variant_id,p_start,p_end);
  return greatest(v_stock - v_reserved,0);
end;
$$;

revoke all on function public.rental_available_stock(uuid,date,date) from public;
revoke all on function public.rental_available_variant_stock(uuid,uuid,date,date) from public;
grant execute on function public.rental_available_stock(uuid,date,date) to anon,authenticated;
grant execute on function public.rental_available_variant_stock(uuid,uuid,date,date) to anon,authenticated;

-- --------------------------------------------------------------------------
-- 5. Ketersediaan untuk JUAL
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
  select stock into v_stock
  from public.items
  where id=p_item_id
    and type='product'
    and is_active=true
    and coalesce(sale_enabled,false)=true;
  if not found then
    raise exception 'Item jual tidak ditemukan atau tidak aktif';
  end if;

  v_peak := public.rental_peak_reserved_stock(p_item_id, null);
  return greatest(v_stock - v_peak, 0);
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
  select v.stock into v_stock
  from public.item_variants v
  join public.items i on i.id=v.item_id
  where v.id=p_variant_id
    and v.item_id=p_item_id
    and v.is_active=true
    and i.type='product'
    and i.is_active=true
    and coalesce(i.sale_enabled,false)=true;
  if not found then
    raise exception 'Varian jual tidak ditemukan atau tidak aktif';
  end if;

  v_peak := public.rental_peak_reserved_stock(p_item_id, p_variant_id);
  return greatest(v_stock - v_peak, 0);
end;
$$;

revoke all on function public.sale_available_stock(uuid) from public;
revoke all on function public.sale_available_variant_stock(uuid,uuid) from public;
grant execute on function public.sale_available_stock(uuid) to anon,authenticated;
grant execute on function public.sale_available_variant_stock(uuid,uuid) to anon,authenticated;

-- --------------------------------------------------------------------------
-- 6. create_order baru: fulfillment_type wajib untuk product
-- --------------------------------------------------------------------------
drop function if exists public.create_order(jsonb,jsonb,text,text);
drop function if exists public.create_order(jsonb,jsonb,text,text,date,date);
drop function if exists public.create_order(jsonb,jsonb,text,text,date,date,jsonb);

create or replace function public.create_order(
  p_customer jsonb,
  p_items jsonb,
  p_voucher_code text default null,
  p_notes text default null,
  p_rental_start date default null,
  p_rental_end date default null,
  p_trip_participants jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_email text := coalesce(auth.jwt() ->> 'email','');
  v_order_id uuid;
  v_order_number text;
  v_line jsonb;
  v_item public.items%rowtype;
  v_variant public.item_variants%rowtype;
  v_variant_id uuid;
  v_item_id uuid;
  v_quantity integer;
  v_fulfillment text;
  v_days integer := 1;
  v_min_days integer := 1;
  v_max_days integer := 30;
  v_has_rental boolean := false;
  v_available integer;
  v_package_price numeric;
  v_unit_price numeric;
  v_subtotal numeric := 0;
  v_discount numeric := 0;
  v_total numeric := 0;
  v_voucher_code text := nullif(upper(trim(coalesce(p_voucher_code,''))),'');
  v_voucher public.vouchers%rowtype;
  v_requires_guarantee boolean := false;
  v_participant jsonb;
  v_trip_detail public.trip_details%rowtype;
  v_peak integer;
  v_cart_rental integer;
  v_sale_reserved integer;
  v_cart_sale integer;
begin
  if v_user_id is null then raise exception 'Silakan login terlebih dahulu'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 then
    raise exception 'Keranjang kosong';
  end if;

  if nullif(trim(p_customer ->> 'full_name'),'') is null
     or nullif(trim(p_customer ->> 'phone'),'') is null
     or nullif(trim(p_customer ->> 'address'),'') is null
     or nullif(trim(p_customer ->> 'city'),'') is null
     or nullif(trim(p_customer ->> 'identity_type'),'') is null
     or char_length(trim(coalesce(p_customer ->> 'identity_last4',''))) <> 4
     or nullif(trim(p_customer ->> 'emergency_contact_name'),'') is null
     or nullif(trim(p_customer ->> 'emergency_contact_phone'),'') is null then
    raise exception 'Identitas belum lengkap';
  end if;

  if p_rental_start is not null and p_rental_end is not null then
    v_days := (p_rental_end - p_rental_start) + 1;
  end if;

  select
    greatest(1,coalesce((settings->>'rental_min_days')::integer,1)),
    greatest(1,coalesce((settings->>'rental_max_days')::integer,30))
  into v_min_days,v_max_days
  from public.site_settings where id='main';

  v_min_days := coalesce(v_min_days,1);
  v_max_days := greatest(v_min_days,coalesce(v_max_days,30));

  -- Satu lock global untuk mencegah dua checkout menghitung reservation/stock
  -- dengan kondisi yang sama lalu lolos bersamaan.
  perform pg_advisory_xact_lock(hashtextextended('abidzar-jual-sewa-inventory-v3',0));

  -- Validasi dan hitung subtotal.
  for v_line in select value from jsonb_array_elements(p_items) loop
    begin
      v_item_id := (v_line->>'item_id')::uuid;
      v_quantity := (v_line->>'quantity')::integer;
      v_variant_id := nullif(v_line->>'variant_id','')::uuid;
    exception when others then
      raise exception 'Format item keranjang tidak valid';
    end;

    v_fulfillment := lower(trim(coalesce(v_line->>'fulfillment_type','')));

    select * into v_item from public.items
    where id=v_item_id and is_active=true;
    if not found then raise exception 'Salah satu item tidak tersedia'; end if;
    if v_quantity < 1 or v_quantity > 99 then raise exception 'Jumlah item tidak valid'; end if;

    if v_item.type='trip' then
      if v_fulfillment <> 'trip' then
        raise exception 'Open Trip harus menggunakan fulfillment_type trip';
      end if;

      if nullif(v_line->>'trip_date','') is null then
        raise exception 'Tanggal perjalanan % wajib dipilih peserta',v_item.title;
      end if;
      if (v_line->>'trip_date')::date < current_date then
        raise exception 'Tanggal perjalanan % tidak boleh tanggal yang sudah lewat',v_item.title;
      end if;

      select * into v_trip_detail from public.trip_details where item_id=v_item.id;
      if found then
        if v_trip_detail.status <> 'open' then
          raise exception 'Trip % tidak sedang dibuka',v_item.title;
        end if;
        if v_trip_detail.registration_deadline is not null and now()>v_trip_detail.registration_deadline then
          raise exception 'Pendaftaran trip % sudah ditutup',v_item.title;
        end if;
      end if;

      select coalesce(v_item.quota,0)-count(*) into v_available
      from public.trip_participants tp
      join public.orders trip_order on trip_order.id=tp.order_id
      where tp.item_id=v_item.id
        and tp.status<>'cancelled'
        and trip_order.status not in ('cancelled','failed','refunded');
      if v_available<v_quantity then raise exception 'Kuota % tidak cukup',v_item.title; end if;
      v_subtotal := v_subtotal + (v_item.price*v_quantity);

    elsif v_item.type='product' then
      if v_fulfillment not in ('sale','rental') then
        raise exception 'Item % harus memiliki fulfillment_type sale atau rental',v_item.title;
      end if;

      if v_variant_id is not null then
        select * into v_variant from public.item_variants
        where id=v_variant_id and item_id=v_item.id and is_active=true;
        if not found then raise exception 'Ukuran atau kapasitas tidak valid'; end if;
      else
        v_variant_id := null;
        if exists(select 1 from public.item_variants where item_id=v_item.id and is_active=true) then
          raise exception 'Pilih ukuran atau kapasitas untuk %',v_item.title;
        end if;
      end if;

      if v_fulfillment='rental' then
        if coalesce(v_item.rental_enabled,true) is false then
          raise exception 'Sewa untuk % sedang dinonaktifkan',v_item.title;
        end if;
        v_has_rental := true;
        if p_rental_start is null or p_rental_end is null or v_days<1 then
          raise exception 'Tanggal ambil dan kembali wajib diisi untuk sewa';
        end if;
        if p_rental_start<current_date then
          raise exception 'Tanggal ambil tidak boleh sebelum hari ini';
        end if;
        if v_days<v_min_days or v_days>v_max_days then
          raise exception 'Durasi sewa harus antara % sampai % hari',v_min_days,v_max_days;
        end if;

        if v_variant_id is not null then
          v_available := public.rental_available_variant_stock(v_item.id,v_variant_id,p_rental_start,p_rental_end);
          select coalesce(sum((x.value->>'quantity')::integer),0) into v_cart_rental
          from jsonb_array_elements(p_items) x
          where lower(trim(coalesce(x.value->>'fulfillment_type','')))='rental'
            and (x.value->>'item_id')::uuid=v_item.id
            and nullif(x.value->>'variant_id','')::uuid=v_variant_id;
        else
          v_available := public.rental_available_stock(v_item.id,p_rental_start,p_rental_end);
          select coalesce(sum((x.value->>'quantity')::integer),0) into v_cart_rental
          from jsonb_array_elements(p_items) x
          where lower(trim(coalesce(x.value->>'fulfillment_type','')))='rental'
            and (x.value->>'item_id')::uuid=v_item.id
            and nullif(x.value->>'variant_id','') is null;
        end if;
        if v_available<coalesce(v_cart_rental,0) then
          raise exception 'Stok sewa % pada tanggal tersebut hanya % unit',v_item.title,v_available;
        end if;

        select price into v_package_price
        from public.item_price_tiers
        where item_id=v_item.id
          and duration_days=v_days
          and (variant_id=v_variant_id or variant_id is null)
        order by (variant_id=v_variant_id) desc limit 1;

        v_unit_price := case when v_package_price is not null then v_package_price else v_item.price*v_days end;
      else
        if coalesce(v_item.sale_enabled,false) is false then
          raise exception 'Penjualan % sedang dinonaktifkan',v_item.title;
        end if;

        if v_variant_id is not null then
          v_available := public.sale_available_variant_stock(v_item.id,v_variant_id);
        else
          v_available := public.sale_available_stock(v_item.id);
        end if;
        if v_available<v_quantity then
          raise exception 'Stok jual % hanya % unit karena sebagian stok sudah berkomitmen untuk rental',v_item.title,v_available;
        end if;

        v_unit_price := v_item.sale_price;
        if v_unit_price<=0 then raise exception 'Harga jual % belum diatur',v_item.title; end if;
      end if;

      v_subtotal := v_subtotal + (v_unit_price*v_quantity);
    end if;

    v_requires_guarantee := v_requires_guarantee or v_item.requires_guarantee;
  end loop;

  -- Pastikan checkout sale + rental dalam keranjang yang sama ikut memperhitungkan
  -- reservation rental dari keranjang sendiri ketika menghitung batas sale.
  for v_line in select value from jsonb_array_elements(p_items) loop
    v_fulfillment := lower(trim(coalesce(v_line->>'fulfillment_type','')));
    if v_fulfillment <> 'sale' then continue; end if;
    v_item_id := (v_line->>'item_id')::uuid;
    v_variant_id := nullif(v_line->>'variant_id','')::uuid;
    v_quantity := (v_line->>'quantity')::integer;

    select coalesce(sum((x.value->>'quantity')::integer),0) into v_cart_sale
    from jsonb_array_elements(p_items) x
    where lower(trim(coalesce(x.value->>'fulfillment_type','')))='sale'
      and (x.value->>'item_id')::uuid=v_item_id
      and (
        (v_variant_id is null and nullif(x.value->>'variant_id','') is null)
        or nullif(x.value->>'variant_id','')::uuid=v_variant_id
      );

    if v_variant_id is not null then
      v_peak := public.rental_peak_reserved_stock(v_item_id,v_variant_id);
      select coalesce(sum((x.value->>'quantity')::integer),0) into v_cart_rental
      from jsonb_array_elements(p_items) x
      where lower(trim(coalesce(x.value->>'fulfillment_type','')))='rental'
        and (x.value->>'item_id')::uuid=v_item_id
        and nullif(x.value->>'variant_id','')::uuid=v_variant_id;
      v_sale_reserved := v_peak + coalesce(v_cart_rental,0);
      select stock into v_available from public.item_variants where id=v_variant_id for update;
    else
      v_peak := public.rental_peak_reserved_stock(v_item_id,null);
      select coalesce(sum((x.value->>'quantity')::integer),0) into v_cart_rental
      from jsonb_array_elements(p_items) x
      where lower(trim(coalesce(x.value->>'fulfillment_type','')))='rental'
        and (x.value->>'item_id')::uuid=v_item_id
        and nullif(x.value->>'variant_id','') is null;
      v_sale_reserved := v_peak + coalesce(v_cart_rental,0);
      select stock into v_available from public.items where id=v_item_id for update;
    end if;

    if v_available - v_sale_reserved < v_cart_sale then
      raise exception 'Stok jual item tidak cukup setelah memperhitungkan rental yang sudah berkomitmen';
    end if;
  end loop;

  if v_requires_guarantee and (
    nullif(trim(p_customer->>'guarantee_type'),'') is null or
    nullif(trim(p_customer->>'guarantee_notes'),'') is null
  ) then raise exception 'Pesanan ini memerlukan jaminan'; end if;

  if v_voucher_code is not null then
    select * into v_voucher from public.vouchers
    where code=v_voucher_code and is_active=true
      and now() between starts_at and expires_at and used_count<quota;
    if not found then raise exception 'Voucher tidak valid atau kuota habis'; end if;
    if not public.voucher_scope_matches(v_voucher,p_items) then
      raise exception 'Voucher tidak berlaku untuk isi keranjang ini';
    end if;
    if v_voucher.once_per_customer and exists(
      select 1 from public.orders o
      where o.user_id=v_user_id and o.voucher_code=v_voucher.code
        and o.status not in ('cancelled','failed','refunded')
    ) then raise exception 'Voucher hanya dapat digunakan satu kali per pelanggan'; end if;
    if v_subtotal<v_voucher.min_purchase then
      raise exception 'Minimal pembelian voucher adalah %',v_voucher.min_purchase;
    end if;
    v_discount := case when v_voucher.discount_type='percent'
      then v_subtotal*(v_voucher.discount_value/100)
      else v_voucher.discount_value end;
    if v_voucher.max_discount is not null then
      v_discount := least(v_discount,v_voucher.max_discount);
    end if;
    v_discount := least(greatest(v_discount,0),v_subtotal);
  end if;

  v_total := v_subtotal-v_discount;
  v_order_number := 'AOC-'||to_char(clock_timestamp(),'YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));

  insert into public.orders(
    order_number,user_id,customer_name,customer_email,phone,address,city,postal_code,
    identity_type,identity_last4,emergency_contact_name,emergency_contact_phone,
    guarantee_type,guarantee_notes,customer_notes,voucher_code,subtotal,discount,total,
    rental_start,rental_end,rental_days,pending_expires_at
  ) values(
    v_order_number,v_user_id,trim(p_customer->>'full_name'),v_email,
    trim(p_customer->>'phone'),trim(p_customer->>'address'),trim(p_customer->>'city'),
    nullif(trim(p_customer->>'postal_code'),''),trim(p_customer->>'identity_type'),
    trim(p_customer->>'identity_last4'),trim(p_customer->>'emergency_contact_name'),
    trim(p_customer->>'emergency_contact_phone'),nullif(trim(p_customer->>'guarantee_type'),''),
    nullif(trim(p_customer->>'guarantee_notes'),''),nullif(trim(p_notes),''),
    v_voucher_code,v_subtotal,v_discount,v_total,
    case when v_has_rental then p_rental_start else null end,
    case when v_has_rental then p_rental_end else null end,
    case when v_has_rental then v_days else null end,
    now() + interval '30 minutes'
  ) returning id into v_order_id;

  for v_line in select value from jsonb_array_elements(p_items) loop
    v_item_id := (v_line->>'item_id')::uuid;
    v_quantity := (v_line->>'quantity')::integer;
    v_variant_id := nullif(v_line->>'variant_id','')::uuid;
    v_fulfillment := lower(trim(coalesce(v_line->>'fulfillment_type','')));
    select * into v_item from public.items where id=v_item_id;

    v_package_price := null;
    v_unit_price := v_item.price;

    if v_item.type='product' then
      if v_variant_id is not null then
        select * into v_variant from public.item_variants where id=v_variant_id and item_id=v_item.id and is_active=true;
      else
        v_variant := null;
      end if;

      if v_fulfillment='rental' then
        select price into v_package_price
        from public.item_price_tiers
        where item_id=v_item.id and duration_days=v_days
          and (variant_id=v_variant_id or variant_id is null)
        order by (variant_id=v_variant_id) desc limit 1;
        v_unit_price := case when v_package_price is not null then v_package_price else v_item.price*v_days end;
      elsif v_fulfillment='sale' then
        v_unit_price := v_item.sale_price;
      end if;
    end if;

    insert into public.order_items(
      order_id,item_id,variant_id,variant_name_snapshot,title_snapshot,item_type,
      fulfillment_type,price_snapshot,quantity,line_total,trip_date_snapshot,
      rental_start,rental_end,rental_days
    ) values(
      v_order_id,v_item.id,v_variant_id,
      case when v_variant_id is null then null else concat_ws(' · ',v_variant.name,nullif(v_variant.capacity,'')) end,
      v_item.title,v_item.type,v_fulfillment,v_unit_price,v_quantity,v_unit_price*v_quantity,
      case when v_item.type='trip' then (v_line->>'trip_date')::date else null end,
      case when v_fulfillment='rental' then p_rental_start else null end,
      case when v_fulfillment='rental' then p_rental_end else null end,
      case when v_fulfillment='rental' then v_days else 1 end
    );
  end loop;

  for v_participant in select value from jsonb_array_elements(p_trip_participants) loop
    select * into v_trip_detail from public.trip_details where item_id=(v_participant->>'item_id')::uuid;
    if nullif(trim(v_participant->>'full_name'),'') is null
       or nullif(trim(v_participant->>'phone'),'') is null
       or nullif(trim(v_participant->>'emergency_contact_name'),'') is null
       or nullif(trim(v_participant->>'emergency_contact_phone'),'') is null then
      raise exception 'Nama, telepon, dan kontak darurat peserta wajib diisi';
    end if;
    if v_trip_detail.min_age is not null and (v_participant->>'age')::integer<v_trip_detail.min_age then
      raise exception 'Usia peserta di bawah batas minimum';
    end if;
    if v_trip_detail.max_age is not null and (v_participant->>'age')::integer>v_trip_detail.max_age then
      raise exception 'Usia peserta di atas batas maksimum';
    end if;
    insert into public.trip_participants(
      order_id,item_id,user_id,seat_number,full_name,phone,age,identity_last4,
      emergency_contact_name,emergency_contact_phone,notes
    ) values(
      v_order_id,(v_participant->>'item_id')::uuid,v_user_id,(v_participant->>'seat_number')::integer,
      trim(v_participant->>'full_name'),trim(v_participant->>'phone'),(v_participant->>'age')::integer,
      nullif(trim(v_participant->>'identity_last4'),''),trim(v_participant->>'emergency_contact_name'),
      trim(v_participant->>'emergency_contact_phone'),nullif(trim(v_participant->>'notes'),'')
    );
  end loop;

  update public.profiles set
    full_name=trim(p_customer->>'full_name'),phone=trim(p_customer->>'phone'),
    address=trim(p_customer->>'address'),city=trim(p_customer->>'city'),
    postal_code=nullif(trim(p_customer->>'postal_code'),'')
  where id=v_user_id;

  return jsonb_build_object(
    'order_id',v_order_id,'order_number',v_order_number,'subtotal',v_subtotal,
    'discount',v_discount,'total',v_total,'status','pending',
    'rental_start',case when v_has_rental then p_rental_start else null end,
    'rental_end',case when v_has_rental then p_rental_end else null end,
    'rental_days',case when v_has_rental then v_days else null end
  );
end;
$$;

revoke all on function public.create_order(jsonb,jsonb,text,text,date,date,jsonb) from public;
grant execute on function public.create_order(jsonb,jsonb,text,text,date,date,jsonb) to authenticated;

-- --------------------------------------------------------------------------
-- 7. Trigger stok: HANYA SALE yang mengurangi/menambah stok
-- --------------------------------------------------------------------------
create or replace function public.sync_sale_stock_from_order_status()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_line public.order_items%rowtype;
begin
  -- PAID: potong stok sale satu kali.
  if new.status='paid' and old.status<>'paid' then
    for v_line in
      select * from public.order_items
      where order_id=new.id
        and item_type='product'
        and fulfillment_type='sale'
        and not coalesce(stock_deducted,false)
      for update
    loop
      -- Pembayaran adalah titik final penjualan. Cek ulang rental commitment
      -- di sini agar order sale yang menunggu pembayaran tidak mengambil stok
      -- yang baru saja dipesan untuk rental.
      if v_line.variant_id is not null then
        if public.sale_available_variant_stock(v_line.item_id,v_line.variant_id) < v_line.quantity then
          raise exception 'Stok jual % tidak cukup ketika pembayaran dikonfirmasi karena sudah berkomitmen untuk rental',v_line.title_snapshot;
        end if;
        update public.item_variants
        set stock=stock-v_line.quantity
        where id=v_line.variant_id and item_id=v_line.item_id and stock>=v_line.quantity;
      else
        if public.sale_available_stock(v_line.item_id) < v_line.quantity then
          raise exception 'Stok jual % tidak cukup ketika pembayaran dikonfirmasi karena sudah berkomitmen untuk rental',v_line.title_snapshot;
        end if;
        update public.items
        set stock=stock-v_line.quantity
        where id=v_line.item_id and stock>=v_line.quantity;
      end if;

      if not found then
        raise exception 'Stok jual % tidak cukup ketika pembayaran dikonfirmasi',v_line.title_snapshot;
      end if;

      update public.order_items set stock_deducted=true where id=v_line.id;
    end loop;
  end if;

  -- CANCELLED setelah PAID: kembalikan stok sale tepat satu kali.
  -- COMPLETED tidak mengembalikan stok karena barang sudah terjual.
  if new.status='cancelled' and old.status='paid' then
    for v_line in
      select * from public.order_items
      where order_id=new.id
        and item_type='product'
        and fulfillment_type='sale'
        and coalesce(stock_deducted,false)
      for update
    loop
      if v_line.variant_id is not null then
        update public.item_variants set stock=stock+v_line.quantity where id=v_line.variant_id;
      else
        update public.items set stock=stock+v_line.quantity where id=v_line.item_id;
      end if;
      update public.order_items set stock_deducted=false where id=v_line.id;
    end loop;
  end if;

  return new;
end;
$$;

drop trigger if exists orders_sync_rental_stock_trigger on public.orders;
drop trigger if exists orders_sync_sale_stock_trigger on public.orders;
create trigger orders_sync_sale_stock_trigger
after update of status on public.orders
for each row
when (old.status is distinct from new.status)
execute function public.sync_sale_stock_from_order_status();

-- Data lama yang stock_deducted=true pada product belum bisa dibedakan antara
-- jual/sewa karena versi lama tidak punya fulfillment_type. Jangan mengubah
-- angka stok historis secara otomatis. Mulai setelah migrasi ini, flag tersebut
-- hanya digunakan untuk fulfillment_type='sale'.

-- --------------------------------------------------------------------------
-- 8. Proteksi return: return hanya untuk rental dan tidak pernah mengubah stock
-- --------------------------------------------------------------------------
create or replace function public.admin_manage_order(
  p_order_id uuid,
  p_action text,
  p_amount numeric default null,
  p_reason text default null,
  p_condition text default null,
  p_item_id uuid default null,
  p_quantity integer default 1
)
returns void
language plpgsql
security definer
set search_path=public
as $$
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
    update public.orders
    set status='cancelled',cancellation_reason=trim(p_reason),cancelled_at=now()
    where id=p_order_id;

  elsif p_action='refund' then
    if coalesce(p_amount,0)<=0 then raise exception 'Nominal refund harus lebih dari 0'; end if;
    select coalesce(sum(amount),0) into v_refunded
    from public.order_refunds where order_id=p_order_id and status<>'failed';
    if v_refunded+p_amount>v_order.total then raise exception 'Total refund melebihi nilai pesanan'; end if;
    select id into v_payment_id from public.payment_transactions where order_id=p_order_id order by created_at desc limit 1;
    insert into public.order_refunds(order_id,payment_transaction_id,amount,refund_type,reason,status,created_by)
    values(p_order_id,v_payment_id,p_amount,case when v_refunded+p_amount>=v_order.total then 'full' else 'partial' end,
      coalesce(nullif(trim(p_reason),''),'Refund admin'),'recorded',auth.uid());
    if v_refunded+p_amount>=v_order.total then
      update public.orders set payment_status='refunded',status='cancelled' where id=p_order_id;
    end if;

  elsif p_action='late_fee' then
    update public.orders set late_fee=greatest(coalesce(p_amount,0),0) where id=p_order_id;

  elsif p_action='deposit_received' then
    update public.orders set deposit_amount=greatest(coalesce(p_amount,0),0),deposit_status='received',deposit_received_at=now() where id=p_order_id;

  elsif p_action='deposit_returned' then
    update public.orders set deposit_status='returned',deposit_returned_at=now() where id=p_order_id;

  elsif p_action='return' then
    if p_condition not in ('good','dirty','damaged','lost') then raise exception 'Kondisi pengembalian tidak valid'; end if;
    select * into v_line
    from public.order_items
    where order_id=p_order_id and item_id=p_item_id
      and item_type='product' and fulfillment_type='rental'
    for update;
    if not found then raise exception 'Item rental tidak ditemukan dalam pesanan'; end if;
    if v_order.status not in ('paid','completed','returned') then
      raise exception 'Pengembalian hanya dapat diproses setelah status Dibayar';
    end if;

    v_return := least(greatest(coalesce(p_quantity,1),1),v_line.quantity-v_line.returned_quantity);
    if v_return<=0 then raise exception 'Seluruh unit item ini sudah dikembalikan'; end if;

    insert into public.order_returns(order_id,item_id,quantity,condition,fee,notes,inspected_by)
    values(p_order_id,p_item_id,v_return,p_condition,greatest(coalesce(p_amount,0),0),nullif(trim(p_reason),''),auth.uid());

    update public.order_items
    set returned_quantity=returned_quantity+v_return,
        stock_deducted=false
    where id=v_line.id;

    update public.orders
    set returned_at=now(),return_condition=p_condition,
        inspection_notes=nullif(trim(p_reason),''),
        late_fee=late_fee+greatest(coalesce(p_amount,0),0)
    where id=p_order_id;

    -- PENTING: tidak ada UPDATE items/item_variants + quantity di sini.
    if not exists(
      select 1 from public.order_items
      where order_id=p_order_id
        and item_type='product'
        and fulfillment_type='rental'
        and returned_quantity<quantity
    ) then
      update public.orders set status='completed' where id=p_order_id and status<>'completed';
    end if;

  else
    raise exception 'Aksi tidak dikenal';
  end if;
end;
$$;

revoke all on function public.admin_manage_order(uuid,text,numeric,text,text,uuid,integer) from public;
grant execute on function public.admin_manage_order(uuid,text,numeric,text,text,uuid,integer) to authenticated;

-- --------------------------------------------------------------------------
-- 9. View ringkasan stok jual/sewa
-- --------------------------------------------------------------------------
create or replace view public.item_sale_rental_summary
with (security_invoker=true) as
select
  i.id as item_id,
  i.title,
  i.stock as physical_stock,
  i.sale_enabled,
  i.rental_enabled,
  i.sale_price,
  public.rental_peak_reserved_stock(i.id,null) as rental_committed_peak,
  greatest(i.stock-public.rental_peak_reserved_stock(i.id,null),0) as sale_available
from public.items i
where i.type='product';

grant select on public.item_sale_rental_summary to anon,authenticated;

notify pgrst,'reload schema';
commit;
