-- AbidzarOutdoorcamp - Sistem Penyewaan Berdasarkan Tanggal
-- Jalankan SETELAH backup.txt dan site-settings.sql.

alter table public.orders add column if not exists rental_start date;
alter table public.orders add column if not exists rental_end date;
alter table public.orders add column if not exists rental_days integer;

alter table public.order_items add column if not exists rental_start date;
alter table public.order_items add column if not exists rental_end date;
alter table public.order_items add column if not exists rental_days integer not null default 1;
alter table public.order_items
  add column if not exists variant_id uuid references public.item_variants(id) on delete set null,
  add column if not exists variant_name_snapshot text;

create index if not exists orders_rental_range_idx
  on public.orders(rental_start, rental_end)
  where rental_start is not null and status <> 'cancelled';

create index if not exists order_items_rental_item_idx
  on public.order_items(item_id, rental_start, rental_end)
  where item_type = 'product';

-- Ganti pemeriksaan total lama agar item sewa dapat dikalikan jumlah hari.
do $$
declare v_constraint text;
begin
  for v_constraint in
    select conname
    from pg_constraint
    where conrelid = 'public.order_items'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%line_total%price_snapshot%quantity%'
  loop
    execute format('alter table public.order_items drop constraint %I', v_constraint);
  end loop;
end $$;

alter table public.order_items
  drop constraint if exists order_items_rental_total_check;
update public.order_items
set price_snapshot = line_total / quantity
where quantity > 0
  and line_total is distinct from price_snapshot * quantity;
alter table public.order_items
  add constraint order_items_rental_total_check check (
    line_total = price_snapshot * quantity
  );

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
  where id = p_item_id and type = 'product' and is_active = true;

  if not found then
    raise exception 'Item sewa tidak ditemukan';
  end if;

  select coalesce(sum(oi.quantity), 0)::integer into v_reserved
  from public.order_items oi
  join public.orders o on o.id = oi.order_id
  where oi.item_id = p_item_id
    and oi.item_type = 'product'
    and o.status in ('pending', 'confirmed', 'paid')
    and oi.rental_start <= p_end
    and oi.rental_end >= p_start;

  return greatest(v_stock - v_reserved, 0);
end;
$$;

revoke all on function public.rental_available_stock(uuid, date, date) from public;
grant execute on function public.rental_available_stock(uuid, date, date) to anon, authenticated;

create or replace function public.rental_available_variant_stock(
  p_item_id uuid, p_variant_id uuid, p_start date, p_end date
) returns integer language plpgsql security definer set search_path=public as $$
declare v_stock integer; v_reserved integer;
begin
  if p_start is null or p_end is null or p_end < p_start then
    raise exception 'Rentang tanggal sewa tidak valid';
  end if;
  select stock into v_stock from public.item_variants
  where id=p_variant_id and item_id=p_item_id and is_active=true;
  if not found then raise exception 'Ukuran atau kapasitas tidak tersedia'; end if;
  select coalesce(sum(oi.quantity),0)::integer into v_reserved
  from public.order_items oi join public.orders o on o.id=oi.order_id
  where oi.item_id=p_item_id and oi.variant_id=p_variant_id
    and oi.item_type='product'
    and (o.status in ('pending','confirmed') or (o.status='paid' and not coalesce(oi.stock_deducted,false)))
    and oi.rental_start<=p_end and oi.rental_end>=p_start;
  return greatest(v_stock-v_reserved,0);
end; $$;
revoke all on function public.rental_available_variant_stock(uuid,uuid,date,date) from public;
grant execute on function public.rental_available_variant_stock(uuid,uuid,date,date) to anon,authenticated;

drop function if exists public.create_order(jsonb, jsonb, text, text);
drop function if exists public.create_order(jsonb, jsonb, text, text, date, date);

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
  v_email text := coalesce(auth.jwt() ->> 'email', '');
  v_order_id uuid;
  v_order_number text;
  v_line jsonb;
  v_item public.items%rowtype;
  v_variant public.item_variants%rowtype;
  v_variant_id uuid;
  v_item_id uuid;
  v_quantity integer;
  v_days integer := 1;
  v_min_days integer := 1;
  v_max_days integer := 30;
  v_has_rental boolean := false;
  v_available integer;
  v_package_price numeric;
  v_subtotal numeric := 0;
  v_discount numeric := 0;
  v_total numeric := 0;
  v_voucher_code text := nullif(upper(trim(coalesce(p_voucher_code, ''))), '');
  v_voucher public.vouchers%rowtype;
  v_requires_guarantee boolean := false;
  v_participant jsonb;
  v_trip_detail public.trip_details%rowtype;
begin
  if v_user_id is null then raise exception 'Silakan login terlebih dahulu'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Keranjang kosong';
  end if;

  if nullif(trim(p_customer ->> 'full_name'), '') is null
     or nullif(trim(p_customer ->> 'phone'), '') is null
     or nullif(trim(p_customer ->> 'address'), '') is null
     or nullif(trim(p_customer ->> 'city'), '') is null
     or nullif(trim(p_customer ->> 'identity_type'), '') is null
     or char_length(trim(coalesce(p_customer ->> 'identity_last4', ''))) <> 4
     or nullif(trim(p_customer ->> 'emergency_contact_name'), '') is null
     or nullif(trim(p_customer ->> 'emergency_contact_phone'), '') is null then
    raise exception 'Identitas belum lengkap';
  end if;

  if p_rental_start is not null and p_rental_end is not null then
    v_days := (p_rental_end - p_rental_start) + 1;
  end if;

  select
    greatest(1, coalesce((settings->>'rental_min_days')::integer, 1)),
    greatest(1, coalesce((settings->>'rental_max_days')::integer, 30))
  into v_min_days, v_max_days
  from public.site_settings where id = 'main';

  v_min_days := coalesce(v_min_days, 1);
  v_max_days := greatest(v_min_days, coalesce(v_max_days, 30));

  -- Mengunci proses reservasi untuk mencegah dua checkout bersamaan
  -- mengambil unit terakhir pada rentang tanggal yang sama.
  perform pg_advisory_xact_lock(hashtextextended('abidzar-rental-booking', 0));

  for v_line in select value from jsonb_array_elements(p_items) loop
    begin
      v_item_id := (v_line ->> 'item_id')::uuid;
      v_quantity := (v_line ->> 'quantity')::integer;
      v_variant_id := nullif(v_line ->> 'variant_id','')::uuid;
    exception when others then
      raise exception 'Format item keranjang tidak valid';
    end;

    select * into v_item from public.items
    where id = v_item_id and is_active = true;
    if not found then raise exception 'Salah satu item tidak tersedia'; end if;
    if v_quantity < 1 or v_quantity > 99 then raise exception 'Jumlah item tidak valid'; end if;

    if v_item.type = 'product' then
      v_has_rental := true;
      if p_rental_start is null or p_rental_end is null or v_days < 1 then
        raise exception 'Tanggal ambil dan kembali wajib diisi';
      end if;
      if p_rental_start < current_date then
        raise exception 'Tanggal ambil tidak boleh sebelum hari ini';
      end if;
      if v_days < v_min_days or v_days > v_max_days then
        raise exception 'Durasi sewa harus antara % sampai % hari', v_min_days, v_max_days;
      end if;

      if exists(select 1 from public.item_variants where item_id=v_item.id and is_active=true) then
        if v_variant_id is null then raise exception 'Pilih ukuran atau kapasitas untuk %',v_item.title; end if;
        select * into v_variant from public.item_variants
        where id=v_variant_id and item_id=v_item.id and is_active=true;
        if not found then raise exception 'Ukuran atau kapasitas % tidak valid',v_item.title; end if;
        v_available := public.rental_available_variant_stock(v_item.id,v_variant_id,p_rental_start,p_rental_end);
      else
        v_variant_id := null;
        v_available := public.rental_available_stock(v_item.id, p_rental_start, p_rental_end);
      end if;
      if v_available < v_quantity then
        raise exception 'Stok % pada tanggal tersebut hanya % unit', v_item.title, v_available;
      end if;
      select price into v_package_price from public.item_price_tiers
      where item_id = v_item.id and duration_days = v_days limit 1;
      v_subtotal := v_subtotal + (
        (case when v_package_price is not null then v_package_price
          else (v_item.price + case when v_variant_id is null then 0 else v_variant.price_adjustment end) * v_days
        end) * v_quantity
      );
    else
      select coalesce(v_item.quota, 0) - count(*) into v_available
      from public.trip_participants tp
      join public.orders trip_order on trip_order.id = tp.order_id
      where tp.item_id = v_item.id and tp.status <> 'cancelled'
        and trip_order.status not in ('cancelled','failed','refunded');
      if v_available < v_quantity then
        raise exception 'Kuota % tidak cukup', v_item.title;
      end if;
      v_subtotal := v_subtotal + (v_item.price * v_quantity);
    end if;

    v_requires_guarantee := v_requires_guarantee or v_item.requires_guarantee;
  end loop;

  if v_requires_guarantee and (
    nullif(trim(p_customer ->> 'guarantee_type'), '') is null or
    nullif(trim(p_customer ->> 'guarantee_notes'), '') is null
  ) then raise exception 'Pesanan ini memerlukan jaminan'; end if;

  if v_voucher_code is not null then
    select * into v_voucher from public.vouchers
    where code = v_voucher_code and is_active = true
      and now() between starts_at and expires_at and used_count < quota;
    if not found then raise exception 'Voucher tidak valid atau kuota habis'; end if;
    if not public.voucher_scope_matches(v_voucher, p_items) then
      raise exception 'Voucher tidak berlaku untuk isi keranjang ini';
    end if;
    if v_voucher.once_per_customer and exists (
      select 1 from public.orders o
      where o.user_id = v_user_id and o.voucher_code = v_voucher.code
        and o.status not in ('cancelled', 'failed', 'refunded')
    ) then
      raise exception 'Voucher hanya dapat digunakan satu kali per pelanggan';
    end if;
    if v_subtotal < v_voucher.min_purchase then
      raise exception 'Minimal pembelian voucher adalah %', v_voucher.min_purchase;
    end if;
    v_discount := case when v_voucher.discount_type = 'percent'
      then v_subtotal * (v_voucher.discount_value / 100)
      else v_voucher.discount_value end;
    if v_voucher.max_discount is not null then
      v_discount := least(v_discount, v_voucher.max_discount);
    end if;
    v_discount := least(greatest(v_discount, 0), v_subtotal);
  end if;

  v_total := v_subtotal - v_discount;
  v_order_number := 'AOC-' || to_char(clock_timestamp(), 'YYYYMMDD') || '-' ||
    upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));

  insert into public.orders (
    order_number, user_id, customer_name, customer_email, phone, address, city,
    postal_code, identity_type, identity_last4, emergency_contact_name,
    emergency_contact_phone, guarantee_type, guarantee_notes, customer_notes,
    voucher_code, subtotal, discount, total, rental_start, rental_end, rental_days
  ) values (
    v_order_number, v_user_id, trim(p_customer ->> 'full_name'), v_email,
    trim(p_customer ->> 'phone'), trim(p_customer ->> 'address'),
    trim(p_customer ->> 'city'), nullif(trim(p_customer ->> 'postal_code'), ''),
    trim(p_customer ->> 'identity_type'), trim(p_customer ->> 'identity_last4'),
    trim(p_customer ->> 'emergency_contact_name'),
    trim(p_customer ->> 'emergency_contact_phone'),
    nullif(trim(p_customer ->> 'guarantee_type'), ''),
    nullif(trim(p_customer ->> 'guarantee_notes'), ''), nullif(trim(p_notes), ''),
    v_voucher_code, v_subtotal, v_discount, v_total,
    case when v_has_rental then p_rental_start else null end,
    case when v_has_rental then p_rental_end else null end,
    case when v_has_rental then v_days else null end
  ) returning id into v_order_id;

  for v_line in select value from jsonb_array_elements(p_items) loop
    v_item_id := (v_line ->> 'item_id')::uuid;
    v_quantity := (v_line ->> 'quantity')::integer;
    v_variant_id := nullif(v_line ->> 'variant_id','')::uuid;
    select * into v_item from public.items where id = v_item_id;
    if v_item.type = 'trip' then
      select * into v_trip_detail from public.trip_details where item_id = v_item.id;
      if found then
        if v_trip_detail.status <> 'open' then raise exception 'Trip % tidak sedang dibuka', v_item.title; end if;
        if v_trip_detail.registration_deadline is not null and now() > v_trip_detail.registration_deadline then raise exception 'Pendaftaran trip % sudah ditutup', v_item.title; end if;
      end if;
      if (select count(*) from jsonb_array_elements(p_trip_participants) p where (p.value->>'item_id')::uuid = v_item.id) <> v_quantity then
        raise exception 'Data peserta % harus diisi untuk setiap kursi', v_item.title;
      end if;
    end if;
    v_package_price := null;
    if v_item.type = 'product' then
      if v_variant_id is not null then
        select * into v_variant from public.item_variants
        where id=v_variant_id and item_id=v_item.id and is_active=true;
        if not found then raise exception 'Ukuran atau kapasitas tidak valid'; end if;
      else
        v_variant_id := null;
      end if;
      select price into v_package_price from public.item_price_tiers
      where item_id = v_item.id and duration_days = v_days limit 1;
    end if;

    insert into public.order_items (
      order_id, item_id, variant_id, variant_name_snapshot, title_snapshot, item_type, price_snapshot, quantity,
      line_total, trip_date_snapshot, rental_start, rental_end, rental_days
    ) values (
      v_order_id, v_item.id, v_variant_id,
      case when v_variant_id is null then null else concat_ws(' · ',v_variant.name,nullif(v_variant.capacity,'')) end,
      v_item.title, v_item.type,
      case when v_item.type = 'product' then
        case when v_package_price is not null then v_package_price
          else (v_item.price + case when v_variant_id is null then 0 else v_variant.price_adjustment end) * v_days end
        else v_item.price end,
      v_quantity,
      (case when v_item.type = 'product' then
        case when v_package_price is not null then v_package_price
          else (v_item.price + case when v_variant_id is null then 0 else v_variant.price_adjustment end) * v_days end
        else v_item.price end) * v_quantity,
      v_item.trip_date,
      case when v_item.type = 'product' then p_rental_start else null end,
      case when v_item.type = 'product' then p_rental_end else null end,
      case when v_item.type = 'product' then v_days else 1 end
    );
  end loop;

  for v_participant in select value from jsonb_array_elements(p_trip_participants) loop
    select * into v_trip_detail from public.trip_details where item_id = (v_participant->>'item_id')::uuid;
    if nullif(trim(v_participant->>'full_name'),'') is null or nullif(trim(v_participant->>'phone'),'') is null
      or nullif(trim(v_participant->>'emergency_contact_name'),'') is null or nullif(trim(v_participant->>'emergency_contact_phone'),'') is null
      then raise exception 'Nama, telepon, dan kontak darurat peserta wajib diisi'; end if;
    if v_trip_detail.min_age is not null and (v_participant->>'age')::integer < v_trip_detail.min_age then raise exception 'Usia peserta di bawah batas minimum'; end if;
    if v_trip_detail.max_age is not null and (v_participant->>'age')::integer > v_trip_detail.max_age then raise exception 'Usia peserta di atas batas maksimum'; end if;
    insert into public.trip_participants(order_id,item_id,user_id,seat_number,full_name,phone,age,identity_last4,emergency_contact_name,emergency_contact_phone,notes)
    values (v_order_id,(v_participant->>'item_id')::uuid,v_user_id,(v_participant->>'seat_number')::integer,trim(v_participant->>'full_name'),trim(v_participant->>'phone'),(v_participant->>'age')::integer,nullif(trim(v_participant->>'identity_last4'),''),trim(v_participant->>'emergency_contact_name'),trim(v_participant->>'emergency_contact_phone'),nullif(trim(v_participant->>'notes'),''));
  end loop;

  update public.profiles set
    full_name = trim(p_customer ->> 'full_name'), phone = trim(p_customer ->> 'phone'),
    address = trim(p_customer ->> 'address'), city = trim(p_customer ->> 'city'),
    postal_code = nullif(trim(p_customer ->> 'postal_code'), '')
  where id = v_user_id;

  return jsonb_build_object(
    'order_id', v_order_id, 'order_number', v_order_number,
    'subtotal', v_subtotal, 'discount', v_discount, 'total', v_total,
    'status', 'pending', 'rental_start', p_rental_start,
    'rental_end', p_rental_end, 'rental_days', case when v_has_rental then v_days else null end
  );
end;
$$;

revoke all on function public.create_order(jsonb, jsonb, text, text, date, date, jsonb) from public;
grant execute on function public.create_order(jsonb, jsonb, text, text, date, date, jsonb) to authenticated;

-- Stok barang sewa sekarang merupakan total unit dan tidak dikurangi permanen.
-- Ketersediaannya dihitung dari pesanan yang rentang tanggalnya bertabrakan.
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
  if p_status not in ('pending', 'confirmed', 'paid', 'completed', 'cancelled') then
    raise exception 'Status tidak valid';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'Pesanan tidak ditemukan'; end if;

  v_old_reserved := v_order.status in ('confirmed', 'paid', 'completed');
  v_new_reserved := p_status in ('confirmed', 'paid', 'completed');

  if not v_old_reserved and v_new_reserved then
    for v_line in select * from public.order_items where order_id = p_order_id loop
      if v_line.item_type = 'trip' then
        update public.items set quota = quota - v_line.quantity
        where id = v_line.item_id and coalesce(quota, 0) >= v_line.quantity;
        if not found then raise exception 'Kuota % tidak cukup', v_line.title_snapshot; end if;
      end if;
    end loop;
    if v_order.voucher_code is not null then
      update public.vouchers set used_count = used_count + 1
      where code = v_order.voucher_code and used_count < quota;
      if not found then raise exception 'Kuota voucher habis'; end if;
    end if;
  elsif v_old_reserved and not v_new_reserved then
    for v_line in select * from public.order_items where order_id = p_order_id loop
      if v_line.item_type = 'trip' then
        update public.items set quota = coalesce(quota, 0) + v_line.quantity
        where id = v_line.item_id;
      end if;
    end loop;
    if v_order.voucher_code is not null then
      update public.vouchers set used_count = greatest(used_count - 1, 0)
      where code = v_order.voucher_code;
    end if;
  end if;

  update public.orders set status = p_status,
    admin_notes = nullif(trim(p_admin_notes), '') where id = p_order_id;
end;
$$;

revoke all on function public.admin_update_order_status(uuid, text, text) from public;
grant execute on function public.admin_update_order_status(uuid, text, text) to authenticated;
