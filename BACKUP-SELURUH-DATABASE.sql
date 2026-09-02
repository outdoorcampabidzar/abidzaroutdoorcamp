-- ============================================================================
-- BACKUP SELURUH DATABASE ABIDZAR OUTDOORCAMP
-- Dibuat otomatis dari seluruh file SQL proyek.
--
-- CARA RESTORE:
-- 1. Buat project Supabase baru.
-- 2. Buka SQL Editor.
-- 3. Salin seluruh isi file ini dan klik Run.
-- 4. Buat akun pengguna pertama, lalu tetapkan Super Admin sesuai petunjuk.
--
-- File ini berisi skema, tabel, indeks, trigger, fungsi/RPC, RLS, Storage bucket,
-- voucher, katalog, open trip, kalender sewa, pembayaran, pesanan, pelanggan,
-- ulasan, notifikasi, stok, penghapusan pesanan, avatar, dan hak akses.
-- ============================================================================

-- ============================================================================
-- BEGIN SOURCE: backup.txt
-- ============================================================================

-- ============================================================================
-- ABIDZAROUTDOORCAMP - FULL DATABASE SCHEMA
-- Version: 2026-07-15
-- Target: Supabase / PostgreSQL
--
-- Isi file ini:
--   profiles, items, ratings, vouchers, orders, order_items, website_ratings
--   trigger registrasi, RLS policies, fungsi order/voucher/admin/rating website
--
-- PENTING:
-- 1. File ini adalah backup STRUKTUR dan LOGIKA database, bukan isi data live.
-- 2. Untuk backup baris data, akun Auth, dan data produksi sebenarnya,
--    jalankan backup-supabase.ps1 yang disertakan dalam paket.
-- 3. Jalankan pada project Supabase baru atau database yang sudah dibackup.
-- ============================================================================

begin;

create extension if not exists "pgcrypto";

-- --------------------------------------------------------------------------
-- TABLES
-- --------------------------------------------------------------------------

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  address text,
  city text,
  postal_code text,
  role text not null default 'user' check (role in ('user', 'admin')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Menambahkan kolom bila tabel berasal dari versi lama.
alter table public.profiles add column if not exists full_name text;
alter table public.profiles add column if not exists phone text;
alter table public.profiles add column if not exists address text;
alter table public.profiles add column if not exists city text;
alter table public.profiles add column if not exists postal_code text;
alter table public.profiles add column if not exists role text not null default 'user';
alter table public.profiles add column if not exists created_at timestamptz not null default now();
alter table public.profiles add column if not exists updated_at timestamptz not null default now();

create table if not exists public.items (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  slug text not null unique,
  type text not null check (type in ('product', 'trip')),
  description text not null default '',
  image_url text not null default '',
  price numeric(14,2) not null default 0 check (price >= 0),
  stock integer not null default 0 check (stock >= 0),
  location text,
  trip_date date,
  quota integer check (quota is null or quota >= 0),
  requires_guarantee boolean not null default false,
  guarantee_note text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.items add column if not exists requires_guarantee boolean not null default false;
alter table public.items add column if not exists guarantee_note text;
alter table public.items add column if not exists updated_at timestamptz not null default now();

create table if not exists public.ratings (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  score integer not null check (score between 1 and 5),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(item_id, user_id)
);

alter table public.ratings add column if not exists updated_at timestamptz not null default now();

create table if not exists public.vouchers (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  discount_type text not null check (discount_type in ('percent', 'fixed')),
  discount_value numeric(14,2) not null check (discount_value > 0),
  min_purchase numeric(14,2) not null default 0 check (min_purchase >= 0),
  max_discount numeric(14,2) check (max_discount is null or max_discount >= 0),
  quota integer not null default 1 check (quota >= 0),
  used_count integer not null default 0 check (used_count >= 0),
  starts_at timestamptz not null,
  expires_at timestamptz not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (expires_at > starts_at),
  check (used_count <= quota)
);

alter table public.vouchers add column if not exists updated_at timestamptz not null default now();

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null unique,
  user_id uuid not null references auth.users(id) on delete restrict,
  customer_name text not null,
  customer_email text not null,
  phone text not null,
  address text not null,
  city text not null,
  postal_code text,
  identity_type text not null,
  identity_last4 text not null check (char_length(identity_last4) = 4),
  emergency_contact_name text not null,
  emergency_contact_phone text not null,
  guarantee_type text,
  guarantee_notes text,
  customer_notes text,
  admin_notes text,
  voucher_code text,
  subtotal numeric(14,2) not null default 0 check (subtotal >= 0),
  discount numeric(14,2) not null default 0 check (discount >= 0),
  total numeric(14,2) not null default 0 check (total >= 0),
  status text not null default 'pending'
    check (status in ('pending', 'confirmed', 'paid', 'completed', 'cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (discount <= subtotal),
  check (total = subtotal - discount)
);

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  item_id uuid not null references public.items(id) on delete restrict,
  title_snapshot text not null,
  item_type text not null check (item_type in ('product', 'trip')),
  price_snapshot numeric(14,2) not null check (price_snapshot >= 0),
  quantity integer not null check (quantity > 0),
  line_total numeric(14,2) not null check (line_total >= 0),
  trip_date_snapshot date,
  created_at timestamptz not null default now(),
  check (line_total = price_snapshot * quantity)
);

create table if not exists public.website_ratings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  score integer not null check (score between 1 and 5),
  comment text check (comment is null or char_length(comment) <= 300),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id)
);

-- --------------------------------------------------------------------------
-- INDEXES
-- --------------------------------------------------------------------------

create index if not exists items_type_active_idx
  on public.items(type, is_active);

create index if not exists items_created_at_idx
  on public.items(created_at desc);

create index if not exists ratings_item_id_idx
  on public.ratings(item_id);

create index if not exists vouchers_code_active_idx
  on public.vouchers(code, is_active);

create index if not exists orders_user_created_idx
  on public.orders(user_id, created_at desc);

create index if not exists orders_status_created_idx
  on public.orders(status, created_at desc);

create index if not exists order_items_order_id_idx
  on public.order_items(order_id);

create index if not exists website_ratings_updated_idx
  on public.website_ratings(updated_at desc);

-- --------------------------------------------------------------------------
-- UPDATED_AT TRIGGER
-- --------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists items_set_updated_at on public.items;
create trigger items_set_updated_at
before update on public.items
for each row execute function public.set_updated_at();

drop trigger if exists ratings_set_updated_at on public.ratings;
create trigger ratings_set_updated_at
before update on public.ratings
for each row execute function public.set_updated_at();

drop trigger if exists vouchers_set_updated_at on public.vouchers;
create trigger vouchers_set_updated_at
before update on public.vouchers
for each row execute function public.set_updated_at();

drop trigger if exists orders_set_updated_at on public.orders;
create trigger orders_set_updated_at
before update on public.orders
for each row execute function public.set_updated_at();

drop trigger if exists website_ratings_set_updated_at on public.website_ratings;
create trigger website_ratings_set_updated_at
before update on public.website_ratings
for each row execute function public.set_updated_at();

-- --------------------------------------------------------------------------
-- AUTH PROFILE SYNC
-- --------------------------------------------------------------------------

create or replace function public.sync_new_registration_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (
    id,
    full_name,
    phone,
    address,
    city,
    postal_code,
    role
  )
  values (
    new.id,
    nullif(trim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), ''),
    nullif(trim(coalesce(new.raw_user_meta_data ->> 'phone', '')), ''),
    nullif(trim(coalesce(new.raw_user_meta_data ->> 'address', '')), ''),
    nullif(trim(coalesce(new.raw_user_meta_data ->> 'city', '')), ''),
    nullif(trim(coalesce(new.raw_user_meta_data ->> 'postal_code', '')), ''),
    'user'
  )
  on conflict (id)
  do update set
    full_name = coalesce(excluded.full_name, public.profiles.full_name),
    phone = coalesce(excluded.phone, public.profiles.phone),
    address = coalesce(excluded.address, public.profiles.address),
    city = coalesce(excluded.city, public.profiles.city),
    postal_code = coalesce(excluded.postal_code, public.profiles.postal_code);

  return new;
end;
$$;

-- Hapus trigger versi lama bila ada.
drop trigger if exists on_auth_user_created on auth.users;
drop trigger if exists zz_sync_registration_profile on auth.users;

create trigger zz_sync_registration_profile
after insert on auth.users
for each row execute function public.sync_new_registration_profile();

-- --------------------------------------------------------------------------
-- ADMIN CHECK
-- --------------------------------------------------------------------------

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and lower(trim(role)) = 'admin'
  );
$$;

-- --------------------------------------------------------------------------
-- PROFILE RPC
-- --------------------------------------------------------------------------

create or replace function public.complete_my_profile(p_profile jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Sesi login tidak ditemukan';
  end if;

  insert into public.profiles (
    id,
    full_name,
    phone,
    address,
    city,
    postal_code,
    role
  )
  values (
    v_user_id,
    nullif(trim(coalesce(p_profile ->> 'full_name', '')), ''),
    nullif(trim(coalesce(p_profile ->> 'phone', '')), ''),
    nullif(trim(coalesce(p_profile ->> 'address', '')), ''),
    nullif(trim(coalesce(p_profile ->> 'city', '')), ''),
    nullif(trim(coalesce(p_profile ->> 'postal_code', '')), ''),
    'user'
  )
  on conflict (id)
  do update set
    full_name = coalesce(excluded.full_name, public.profiles.full_name),
    phone = coalesce(excluded.phone, public.profiles.phone),
    address = coalesce(excluded.address, public.profiles.address),
    city = coalesce(excluded.city, public.profiles.city),
    postal_code = coalesce(excluded.postal_code, public.profiles.postal_code);
end;
$$;

-- --------------------------------------------------------------------------
-- VOUCHER RPC
-- --------------------------------------------------------------------------

create or replace function public.preview_voucher(
  p_code text,
  p_subtotal numeric
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v public.vouchers%rowtype;
  v_discount numeric := 0;
  v_code text := upper(trim(coalesce(p_code, '')));
begin
  if auth.uid() is null then
    raise exception 'Silakan login terlebih dahulu';
  end if;

  if p_subtotal is null or p_subtotal < 0 then
    raise exception 'Subtotal tidak valid';
  end if;

  select *
  into v
  from public.vouchers
  where code = v_code
    and is_active = true
    and now() between starts_at and expires_at
    and used_count < quota;

  if not found then
    raise exception 'Voucher tidak valid, berakhir, atau kuota habis';
  end if;

  if p_subtotal < v.min_purchase then
    raise exception 'Minimal pembelian voucher adalah %', v.min_purchase;
  end if;

  v_discount := case
    when v.discount_type = 'percent'
      then p_subtotal * (v.discount_value / 100)
    else v.discount_value
  end;

  if v.max_discount is not null then
    v_discount := least(v_discount, v.max_discount);
  end if;

  v_discount := least(greatest(v_discount, 0), p_subtotal);

  return jsonb_build_object(
    'code', v.code,
    'discount', v_discount,
    'total', p_subtotal - v_discount
  );
end;
$$;

-- --------------------------------------------------------------------------
-- CREATE ORDER RPC
-- --------------------------------------------------------------------------

create or replace function public.create_order(
  p_customer jsonb,
  p_items jsonb,
  p_voucher_code text default null,
  p_notes text default null
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
  v_item_id uuid;
  v_quantity integer;
  v_subtotal numeric := 0;
  v_discount numeric := 0;
  v_total numeric := 0;
  v_voucher_code text := nullif(upper(trim(coalesce(p_voucher_code, ''))), '');
  v_voucher public.vouchers%rowtype;
  v_requires_guarantee boolean := false;
begin
  if v_user_id is null then
    raise exception 'Silakan login terlebih dahulu';
  end if;

  if jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
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

  for v_line in
    select value from jsonb_array_elements(p_items)
  loop
    begin
      v_item_id := (v_line ->> 'item_id')::uuid;
      v_quantity := (v_line ->> 'quantity')::integer;
    exception
      when others then
        raise exception 'Format item keranjang tidak valid';
    end;

    select *
    into v_item
    from public.items
    where id = v_item_id
      and is_active = true;

    if not found then
      raise exception 'Salah satu item tidak tersedia';
    end if;

    if v_quantity < 1 or v_quantity > 99 then
      raise exception 'Jumlah item tidak valid';
    end if;

    if v_item.type = 'product' and v_item.stock < v_quantity then
      raise exception 'Stok % tidak cukup', v_item.title;
    end if;

    if v_item.type = 'trip' and coalesce(v_item.quota, 0) < v_quantity then
      raise exception 'Kuota % tidak cukup', v_item.title;
    end if;

    v_subtotal := v_subtotal + (v_item.price * v_quantity);
    v_requires_guarantee := v_requires_guarantee or v_item.requires_guarantee;
  end loop;

  if v_requires_guarantee
     and (
       nullif(trim(p_customer ->> 'guarantee_type'), '') is null
       or nullif(trim(p_customer ->> 'guarantee_notes'), '') is null
     ) then
    raise exception 'Pesanan ini memerlukan jaminan';
  end if;

  if v_voucher_code is not null then
    select *
    into v_voucher
    from public.vouchers
    where code = v_voucher_code
      and is_active = true
      and now() between starts_at and expires_at
      and used_count < quota;

    if not found then
      raise exception 'Voucher tidak valid atau kuota habis';
    end if;

    if v_subtotal < v_voucher.min_purchase then
      raise exception 'Minimal pembelian voucher adalah %', v_voucher.min_purchase;
    end if;

    v_discount := case
      when v_voucher.discount_type = 'percent'
        then v_subtotal * (v_voucher.discount_value / 100)
      else v_voucher.discount_value
    end;

    if v_voucher.max_discount is not null then
      v_discount := least(v_discount, v_voucher.max_discount);
    end if;

    v_discount := least(greatest(v_discount, 0), v_subtotal);
  end if;

  v_total := v_subtotal - v_discount;
  v_order_number :=
    'AOC-' ||
    to_char(clock_timestamp(), 'YYYYMMDD') || '-' ||
    upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));

  insert into public.orders (
    order_number,
    user_id,
    customer_name,
    customer_email,
    phone,
    address,
    city,
    postal_code,
    identity_type,
    identity_last4,
    emergency_contact_name,
    emergency_contact_phone,
    guarantee_type,
    guarantee_notes,
    customer_notes,
    voucher_code,
    subtotal,
    discount,
    total
  )
  values (
    v_order_number,
    v_user_id,
    trim(p_customer ->> 'full_name'),
    v_email,
    trim(p_customer ->> 'phone'),
    trim(p_customer ->> 'address'),
    trim(p_customer ->> 'city'),
    nullif(trim(p_customer ->> 'postal_code'), ''),
    trim(p_customer ->> 'identity_type'),
    trim(p_customer ->> 'identity_last4'),
    trim(p_customer ->> 'emergency_contact_name'),
    trim(p_customer ->> 'emergency_contact_phone'),
    nullif(trim(p_customer ->> 'guarantee_type'), ''),
    nullif(trim(p_customer ->> 'guarantee_notes'), ''),
    nullif(trim(p_notes), ''),
    v_voucher_code,
    v_subtotal,
    v_discount,
    v_total
  )
  returning id into v_order_id;

  for v_line in
    select value from jsonb_array_elements(p_items)
  loop
    v_item_id := (v_line ->> 'item_id')::uuid;
    v_quantity := (v_line ->> 'quantity')::integer;

    select * into v_item
    from public.items
    where id = v_item_id;

    insert into public.order_items (
      order_id,
      item_id,
      title_snapshot,
      item_type,
      price_snapshot,
      quantity,
      line_total,
      trip_date_snapshot
    )
    values (
      v_order_id,
      v_item.id,
      v_item.title,
      v_item.type,
      v_item.price,
      v_quantity,
      v_item.price * v_quantity,
      v_item.trip_date
    );
  end loop;

  update public.profiles
  set
    full_name = trim(p_customer ->> 'full_name'),
    phone = trim(p_customer ->> 'phone'),
    address = trim(p_customer ->> 'address'),
    city = trim(p_customer ->> 'city'),
    postal_code = nullif(trim(p_customer ->> 'postal_code'), '')
  where id = v_user_id;

  return jsonb_build_object(
    'order_id', v_order_id,
    'order_number', v_order_number,
    'subtotal', v_subtotal,
    'discount', v_discount,
    'total', v_total,
    'status', 'pending'
  );
end;
$$;

-- --------------------------------------------------------------------------
-- ADMIN ORDER STATUS RPC
-- --------------------------------------------------------------------------

create or replace function public.admin_update_order_status(
  p_order_id uuid,
  p_status text,
  p_admin_notes text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_line public.order_items%rowtype;
  v_old_reserved boolean;
  v_new_reserved boolean;
begin
  if not public.is_admin() then
    raise exception 'Akses admin diperlukan';
  end if;

  if p_status not in ('pending', 'confirmed', 'paid', 'completed', 'cancelled') then
    raise exception 'Status tidak valid';
  end if;

  select *
  into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Pesanan tidak ditemukan';
  end if;

  v_old_reserved := v_order.status in ('confirmed', 'paid', 'completed');
  v_new_reserved := p_status in ('confirmed', 'paid', 'completed');

  if not v_old_reserved and v_new_reserved then
    for v_line in
      select * from public.order_items where order_id = p_order_id
    loop
      if v_line.item_type = 'product' then
        update public.items
        set stock = stock - v_line.quantity
        where id = v_line.item_id
          and stock >= v_line.quantity;
      else
        update public.items
        set quota = quota - v_line.quantity
        where id = v_line.item_id
          and coalesce(quota, 0) >= v_line.quantity;
      end if;

      if not found then
        raise exception 'Stok/kuota % tidak cukup', v_line.title_snapshot;
      end if;
    end loop;

    if v_order.voucher_code is not null then
      update public.vouchers
      set used_count = used_count + 1
      where code = v_order.voucher_code
        and used_count < quota;

      if not found then
        raise exception 'Kuota voucher habis';
      end if;
    end if;

  elsif v_old_reserved and not v_new_reserved then
    for v_line in
      select * from public.order_items where order_id = p_order_id
    loop
      if v_line.item_type = 'product' then
        update public.items
        set stock = stock + v_line.quantity
        where id = v_line.item_id;
      else
        update public.items
        set quota = coalesce(quota, 0) + v_line.quantity
        where id = v_line.item_id;
      end if;
    end loop;

    if v_order.voucher_code is not null then
      update public.vouchers
      set used_count = greatest(used_count - 1, 0)
      where code = v_order.voucher_code;
    end if;
  end if;

  update public.orders
  set
    status = p_status,
    admin_notes = nullif(trim(p_admin_notes), '')
  where id = p_order_id;
end;
$$;

-- --------------------------------------------------------------------------
-- ADMIN MANAGEMENT RPC
-- --------------------------------------------------------------------------

create or replace function public.list_admin_users()
returns table (
  user_id uuid,
  email text,
  full_name text,
  created_at timestamptz,
  admin_since timestamptz
)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not public.is_admin() then
    raise exception 'Akses administrator diperlukan';
  end if;

  return query
  select
    u.id,
    u.email::text,
    p.full_name::text,
    u.created_at,
    p.updated_at
  from auth.users u
  join public.profiles p on p.id = u.id
  where lower(trim(p.role)) = 'admin'
  order by
    case when u.id = auth.uid() then 0 else 1 end,
    lower(u.email);
end;
$$;

create or replace function public.add_admin_by_email(
  p_email text,
  p_full_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id uuid;
  v_email text;
begin
  if not public.is_admin() then
    raise exception 'Akses administrator diperlukan';
  end if;

  v_email := lower(trim(coalesce(p_email, '')));

  if v_email = '' then
    raise exception 'Email wajib diisi';
  end if;

  select id
  into v_user_id
  from auth.users
  where lower(email) = v_email
  limit 1;

  if v_user_id is null then
    raise exception
      'Pengguna dengan email % belum terdaftar. Minta pengguna mendaftar terlebih dahulu.',
      v_email;
  end if;

  insert into public.profiles (id, full_name, role)
  values (
    v_user_id,
    nullif(trim(p_full_name), ''),
    'admin'
  )
  on conflict (id)
  do update set
    role = 'admin',
    full_name = coalesce(
      nullif(trim(excluded.full_name), ''),
      public.profiles.full_name
    );

  return jsonb_build_object(
    'user_id', v_user_id,
    'email', v_email,
    'role', 'admin'
  );
end;
$$;

create or replace function public.remove_admin_access(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_admin_count integer;
  v_target_is_admin boolean;
begin
  if not public.is_admin() then
    raise exception 'Akses administrator diperlukan';
  end if;

  if p_user_id is null then
    raise exception 'Pengguna tidak valid';
  end if;

  if p_user_id = auth.uid() then
    raise exception 'Anda tidak dapat mencabut akses admin akun sendiri';
  end if;

  select exists (
    select 1
    from public.profiles
    where id = p_user_id
      and lower(trim(role)) = 'admin'
  )
  into v_target_is_admin;

  if not v_target_is_admin then
    raise exception 'Pengguna tersebut bukan administrator';
  end if;

  select count(*)
  into v_admin_count
  from public.profiles
  where lower(trim(role)) = 'admin';

  if v_admin_count <= 1 then
    raise exception 'Administrator terakhir tidak dapat dihapus';
  end if;

  update public.profiles
  set role = 'user'
  where id = p_user_id;
end;
$$;

-- --------------------------------------------------------------------------
-- WEBSITE RATING RPC
-- --------------------------------------------------------------------------

create or replace function public.get_website_rating()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_average numeric := 0;
  v_count bigint := 0;
  v_my_score integer := 0;
  v_my_comment text := '';
begin
  select
    coalesce(round(avg(wr.score)::numeric, 1), 0),
    count(*)
  into v_average, v_count
  from public.website_ratings wr;

  if auth.uid() is not null then
    select
      wr.score,
      coalesce(wr.comment, '')
    into v_my_score, v_my_comment
    from public.website_ratings wr
    where wr.user_id = auth.uid()
    limit 1;

    v_my_score := coalesce(v_my_score, 0);
    v_my_comment := coalesce(v_my_comment, '');
  end if;

  return jsonb_build_object(
    'rating_average', v_average,
    'rating_count', v_count,
    'my_score', v_my_score,
    'my_comment', v_my_comment
  );
end;
$$;

create or replace function public.get_website_reviews(p_limit integer default 6)
returns table (
  display_name text,
  score integer,
  comment text,
  created_at timestamptz,
  updated_at timestamptz,
  is_mine boolean,
  total_count bigint
)
language sql
stable
security definer
set search_path = public, auth
as $$
  with public_reviews as (
    select
      case
        when nullif(trim(coalesce(p.full_name, '')), '') is not null
          then split_part(trim(p.full_name), ' ', 1)
        else 'Pengguna'
      end::text as display_name,
      wr.score,
      wr.comment,
      wr.created_at,
      wr.updated_at,
      (wr.user_id = auth.uid()) as is_mine,
      count(*) over () as total_count
    from public.website_ratings wr
    left join public.profiles p on p.id = wr.user_id
    where nullif(trim(coalesce(wr.comment, '')), '') is not null
    order by
      case when wr.user_id = auth.uid() then 0 else 1 end,
      wr.updated_at desc
  )
  select *
  from public_reviews
  limit greatest(1, least(coalesce(p_limit, 6), 30));
$$;

create or replace function public.save_website_review_v2(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_score integer;
  v_input_comment text;
  v_existing_comment text;
  v_saved_comment text;
  v_average numeric := 0;
  v_count bigint := 0;
begin
  if v_user_id is null then
    raise exception 'Sesi login tidak ditemukan. Silakan login ulang.';
  end if;

  if p_payload is null then
    raise exception 'Data rating tidak ditemukan';
  end if;

  begin
    v_score := (p_payload ->> 'score')::integer;
  exception
    when others then
      raise exception 'Nilai rating tidak valid';
  end;

  if v_score < 1 or v_score > 5 then
    raise exception 'Rating harus antara 1 sampai 5 bintang';
  end if;

  v_input_comment :=
    nullif(trim(coalesce(p_payload ->> 'comment', '')), '');

  if v_input_comment is not null
     and char_length(v_input_comment) > 300 then
    raise exception 'Komentar maksimal 300 karakter';
  end if;

  select wr.comment
  into v_existing_comment
  from public.website_ratings wr
  where wr.user_id = v_user_id
  limit 1;

  -- Input kosong mempertahankan komentar lama.
  v_saved_comment := coalesce(v_input_comment, v_existing_comment);

  insert into public.website_ratings (
    user_id,
    score,
    comment
  )
  values (
    v_user_id,
    v_score,
    v_saved_comment
  )
  on conflict (user_id)
  do update set
    score = excluded.score,
    comment = coalesce(excluded.comment, public.website_ratings.comment);

  select wr.comment
  into v_saved_comment
  from public.website_ratings wr
  where wr.user_id = v_user_id
  limit 1;

  select
    coalesce(round(avg(wr.score)::numeric, 1), 0),
    count(*)
  into v_average, v_count
  from public.website_ratings wr;

  return jsonb_build_object(
    'success', true,
    'rating_average', v_average,
    'rating_count', v_count,
    'my_score', v_score,
    'my_comment', coalesce(v_saved_comment, ''),
    'comment_length', char_length(coalesce(v_saved_comment, ''))
  );
end;
$$;

-- Kompatibilitas fungsi versi lama.
create or replace function public.submit_website_rating(
  p_score integer,
  p_comment text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.save_website_review_v2(
    jsonb_build_object(
      'score', p_score,
      'comment', p_comment
    )
  );
end;
$$;

-- --------------------------------------------------------------------------
-- ROW LEVEL SECURITY
-- --------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.items enable row level security;
alter table public.ratings enable row level security;
alter table public.vouchers enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.website_ratings enable row level security;

-- Profiles
drop policy if exists "profiles own read" on public.profiles;
drop policy if exists "profiles own registration read" on public.profiles;
drop policy if exists "profiles own account read" on public.profiles;
drop policy if exists "profiles own or admin read" on public.profiles;
create policy "profiles own or admin read"
on public.profiles for select
to authenticated
using (id = auth.uid() or public.is_admin());

drop policy if exists "profiles own update" on public.profiles;
drop policy if exists "profiles own registration update" on public.profiles;
drop policy if exists "profiles own account update" on public.profiles;
create policy "profiles own update"
on public.profiles for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid());

-- Items
drop policy if exists "items public read active" on public.items;
create policy "items public read active"
on public.items for select
using (is_active = true or public.is_admin());

drop policy if exists "items admin insert" on public.items;
create policy "items admin insert"
on public.items for insert
to authenticated
with check (public.is_admin());

drop policy if exists "items admin update" on public.items;
create policy "items admin update"
on public.items for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "items admin delete" on public.items;
create policy "items admin delete"
on public.items for delete
to authenticated
using (public.is_admin());

-- Item ratings (legacy/optional)
drop policy if exists "ratings public read" on public.ratings;
create policy "ratings public read"
on public.ratings for select
using (true);

drop policy if exists "ratings own insert" on public.ratings;
create policy "ratings own insert"
on public.ratings for insert
to authenticated
with check (user_id = auth.uid());

drop policy if exists "ratings own update" on public.ratings;
create policy "ratings own update"
on public.ratings for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

-- Vouchers: kode voucher tidak dibuka langsung ke publik.
drop policy if exists "vouchers active read" on public.vouchers;
drop policy if exists "vouchers admin read" on public.vouchers;
create policy "vouchers admin read"
on public.vouchers for select
to authenticated
using (public.is_admin());

drop policy if exists "vouchers admin insert" on public.vouchers;
create policy "vouchers admin insert"
on public.vouchers for insert
to authenticated
with check (public.is_admin());

drop policy if exists "vouchers admin update" on public.vouchers;
create policy "vouchers admin update"
on public.vouchers for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "vouchers admin delete" on public.vouchers;
create policy "vouchers admin delete"
on public.vouchers for delete
to authenticated
using (public.is_admin());

-- Orders
drop policy if exists "orders own or admin read" on public.orders;
create policy "orders own or admin read"
on public.orders for select
to authenticated
using (user_id = auth.uid() or public.is_admin());

drop policy if exists "orders admin update" on public.orders;
create policy "orders admin update"
on public.orders for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Order items
drop policy if exists "order items own or admin read" on public.order_items;
create policy "order items own or admin read"
on public.order_items for select
to authenticated
using (
  exists (
    select 1
    from public.orders o
    where o.id = order_items.order_id
      and (o.user_id = auth.uid() or public.is_admin())
  )
);

-- website_ratings tidak diakses langsung; hanya melalui RPC security definer.
drop policy if exists "website ratings own read" on public.website_ratings;
drop policy if exists "website ratings own insert" on public.website_ratings;
drop policy if exists "website ratings own update" on public.website_ratings;

-- --------------------------------------------------------------------------
-- PRIVILEGES
-- --------------------------------------------------------------------------

grant usage on schema public to anon, authenticated;

grant select on public.items to anon, authenticated;
grant insert, update, delete on public.items to authenticated;

grant select, update on public.profiles to authenticated;

grant select on public.ratings to anon, authenticated;
grant insert, update on public.ratings to authenticated;

grant select, insert, update, delete on public.vouchers to authenticated;

grant select on public.orders, public.order_items to authenticated;
grant update on public.orders to authenticated;

revoke all on public.website_ratings from anon, authenticated;

revoke all on function public.is_admin() from public;
revoke all on function public.complete_my_profile(jsonb) from public;
revoke all on function public.preview_voucher(text, numeric) from public;
revoke all on function public.create_order(jsonb, jsonb, text, text) from public;
revoke all on function public.admin_update_order_status(uuid, text, text) from public;
revoke all on function public.list_admin_users() from public;
revoke all on function public.add_admin_by_email(text, text) from public;
revoke all on function public.remove_admin_access(uuid) from public;
revoke all on function public.get_website_rating() from public;
revoke all on function public.get_website_reviews(integer) from public;
revoke all on function public.save_website_review_v2(jsonb) from public;
revoke all on function public.submit_website_rating(integer, text) from public;

grant execute on function public.is_admin() to authenticated;
grant execute on function public.complete_my_profile(jsonb) to authenticated;
grant execute on function public.preview_voucher(text, numeric) to authenticated;
grant execute on function public.create_order(jsonb, jsonb, text, text) to authenticated;
grant execute on function public.admin_update_order_status(uuid, text, text) to authenticated;
grant execute on function public.list_admin_users() to authenticated;
grant execute on function public.add_admin_by_email(text, text) to authenticated;
grant execute on function public.remove_admin_access(uuid) to authenticated;
grant execute on function public.get_website_rating() to anon, authenticated;
grant execute on function public.get_website_reviews(integer) to anon, authenticated;
grant execute on function public.save_website_review_v2(jsonb) to authenticated;
grant execute on function public.submit_website_rating(integer, text) to authenticated;

notify pgrst, 'reload schema';

commit;

-- --------------------------------------------------------------------------
-- SET ADMIN PERTAMA (JALANKAN SETELAH AKUN SUDAH MENDAFTAR)
-- Ganti alamat email di bawah, lalu hapus tanda komentar.
-- --------------------------------------------------------------------------
-- update public.profiles
-- set role = 'admin'
-- where id = (
--   select id from auth.users
--   where lower(email) = lower('admin@email.com')
-- );

-- --------------------------------------------------------------------------
-- PEMERIKSAAN SETELAH INSTALASI
-- --------------------------------------------------------------------------
select table_name
from information_schema.tables
where table_schema = 'public'
  and table_name in (
    'profiles', 'items', 'ratings', 'vouchers',
    'orders', 'order_items', 'website_ratings'
  )
order by table_name;

-- ============================================================================
-- END SOURCE: backup.txt
-- ============================================================================

-- ============================================================================
-- BEGIN SOURCE: site-settings.sql
-- ============================================================================

-- AbidzarOutdoorcamp - Pengaturan Website
-- Jalankan seluruh file ini satu kali melalui Supabase SQL Editor.

create table if not exists public.site_settings (
  id text primary key,
  settings jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);

alter table public.site_settings enable row level security;

drop policy if exists "site settings dapat dibaca publik" on public.site_settings;
create policy "site settings dapat dibaca publik"
on public.site_settings for select to anon, authenticated
using (id = 'main');

revoke insert, update, delete on public.site_settings from anon, authenticated;
grant select on public.site_settings to anon, authenticated;

insert into public.site_settings (id, settings)
values ('main', jsonb_build_object(
  'site_name', 'AbidzarOutdoorcamp',
  'whatsapp_number', '6289509349428',
  'whatsapp_message', 'Halo CS AbidzarOutdoorcamp, saya ingin bertanya mengenai layanan.',
  'admin_1_name', 'Admin 1', 'admin_1_whatsapp', '',
  'admin_2_name', 'Admin 2', 'admin_2_whatsapp', '',
  'admin_3_name', 'Admin 3', 'admin_3_whatsapp', '',
  'address', '', 'business_hours', '', 'google_maps_url', '',
  'instagram_url', '', 'tiktok_url', '',
  'hero_eyebrow', 'Outdoor rental & open trip',
  'hero_title', 'Siapkan petualangan.',
  'hero_subtitle', 'Pesan semuanya di satu tempat.',
  'hero_description', 'Cari perlengkapan di katalog Sewa Item atau pilih perjalanan di katalog Open Trip. Keduanya tetap dapat digabungkan dalam satu keranjang dan satu checkout.',
  'seo_title', 'AbidzarOutdoorcamp — Sewa Outdoor & Open Trip',
  'seo_description', 'Katalog sewa perlengkapan outdoor dan open trip AbidzarOutdoorcamp.',
  'rental_min_days', 1, 'rental_max_days', 30,
  'payment_enabled', false,
  'payment_method', 'qrisorkut',
  'payment_timeout_minutes', 15,
  'late_fee_text', '', 'guarantee_policy', '',
  'cancellation_policy', '', 'refund_policy', '',
  'maintenance_mode', false,
  'maintenance_message', 'Website sedang dalam perawatan. Silakan hubungi kami melalui WhatsApp.'
)) on conflict (id) do nothing;

create or replace function public.admin_save_site_settings(p_settings jsonb)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  v_is_admin boolean;
  v_settings jsonb;
  v_min_days integer;
  v_max_days integer;
begin
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and lower(trim(coalesce(role, ''))) = 'admin'
  ) into v_is_admin;

  if not v_is_admin then
    raise exception 'Akses administrator diperlukan.';
  end if;

  if p_settings is null or jsonb_typeof(p_settings) <> 'object' then
    raise exception 'Format pengaturan tidak valid.';
  end if;

  begin
    v_min_days := greatest(1, least(365, coalesce((p_settings->>'rental_min_days')::integer, 1)));
    v_max_days := greatest(v_min_days, least(365, coalesce((p_settings->>'rental_max_days')::integer, 30)));
  exception when invalid_text_representation then
    v_min_days := 1;
    v_max_days := 30;
  end;

  v_settings := p_settings || jsonb_build_object(
    'site_name', left(trim(coalesce(p_settings->>'site_name', '')), 120),
    'whatsapp_number', regexp_replace(coalesce(p_settings->>'whatsapp_number', ''), '[^0-9]', '', 'g'),
    'admin_1_whatsapp', regexp_replace(coalesce(p_settings->>'admin_1_whatsapp', ''), '[^0-9]', '', 'g'),
    'admin_2_whatsapp', regexp_replace(coalesce(p_settings->>'admin_2_whatsapp', ''), '[^0-9]', '', 'g'),
    'admin_3_whatsapp', regexp_replace(coalesce(p_settings->>'admin_3_whatsapp', ''), '[^0-9]', '', 'g'),
    'rental_min_days', v_min_days,
    'rental_max_days', v_max_days,
    'maintenance_mode', coalesce((p_settings->>'maintenance_mode')::boolean, false)
  );

  if v_settings->>'site_name' = '' or v_settings->>'whatsapp_number' = '' then
    raise exception 'Nama website dan nomor WhatsApp wajib diisi.';
  end if;

  insert into public.site_settings (id, settings, updated_at, updated_by)
  values ('main', v_settings, now(), auth.uid())
  on conflict (id) do update set
    settings = excluded.settings,
    updated_at = excluded.updated_at,
    updated_by = excluded.updated_by;

  return v_settings;
end;
$$;

revoke all on function public.admin_save_site_settings(jsonb) from public;
grant execute on function public.admin_save_site_settings(jsonb) to authenticated;

-- ============================================================================
-- END SOURCE: site-settings.sql
-- ============================================================================

-- ============================================================================
-- BEGIN SOURCE: catalog-management.sql
-- ============================================================================

-- Pengelolaan katalog lanjutan AbidzarOutdoorcamp
-- Jalankan sekali melalui Supabase SQL Editor.

create table if not exists public.item_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.items
  add column if not exists category_id uuid references public.item_categories(id) on delete set null,
  add column if not exists deposit numeric(14,2) not null default 0,
  add column if not exists is_featured boolean not null default false,
  add column if not exists sort_order integer not null default 0,
  add column if not exists archived_at timestamptz;

create table if not exists public.item_images (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id) on delete cascade,
  image_url text not null,
  alt_text text,
  is_primary boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create unique index if not exists item_images_one_primary_idx
  on public.item_images(item_id) where is_primary;

create table if not exists public.item_variants (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id) on delete cascade,
  name text not null,
  capacity text,
  price_adjustment numeric(14,2) not null default 0,
  stock integer not null default 0 check (stock >= 0),
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.inventory_units (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id) on delete restrict,
  variant_id uuid references public.item_variants(id) on delete set null,
  inventory_number text not null unique,
  condition text not null default 'good'
    check (condition in ('new', 'good', 'fair', 'damaged')),
  status text not null default 'available'
    check (status in ('available', 'rented', 'damaged', 'maintenance', 'retired')),
  notes text,
  purchased_at date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.item_price_tiers (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id) on delete cascade,
  label text not null,
  duration_days integer not null check (duration_days > 0),
  price numeric(14,2) not null check (price >= 0),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  unique(item_id, duration_days)
);
alter table public.item_price_tiers
  add column if not exists variant_id uuid references public.item_variants(id) on delete cascade;
alter table public.item_price_tiers
  drop constraint if exists item_price_tiers_item_id_duration_days_key;
create unique index if not exists item_price_tiers_variant_duration_idx
  on public.item_price_tiers(item_id,variant_id,duration_days)
  where variant_id is not null;
create unique index if not exists item_price_tiers_default_duration_idx
  on public.item_price_tiers(item_id,duration_days)
  where variant_id is null;

create or replace view public.item_inventory_summary
with (security_invoker = true) as
select
  i.id as item_id,
  count(u.id) filter (where u.status = 'available')::integer as available,
  count(u.id) filter (where u.status = 'rented')::integer as rented,
  count(u.id) filter (where u.status = 'damaged')::integer as damaged,
  count(u.id) filter (where u.status = 'maintenance')::integer as maintenance,
  count(u.id) filter (where u.status = 'retired')::integer as retired,
  count(u.id)::integer as total_units
from public.items i
left join public.inventory_units u on u.item_id = i.id
group by i.id;

create index if not exists items_catalog_sort_idx
  on public.items(type, is_featured desc, sort_order, created_at desc)
  where archived_at is null;
create index if not exists inventory_units_item_status_idx
  on public.inventory_units(item_id, status);
create index if not exists item_images_item_sort_idx
  on public.item_images(item_id, sort_order);

alter table public.item_categories enable row level security;
alter table public.item_images enable row level security;
alter table public.item_variants enable row level security;
alter table public.inventory_units enable row level security;
alter table public.item_price_tiers enable row level security;

drop policy if exists "categories public read" on public.item_categories;
create policy "categories public read" on public.item_categories for select
using (is_active or public.is_admin());
drop policy if exists "categories admin write" on public.item_categories;
create policy "categories admin write" on public.item_categories for all
to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "item images public read" on public.item_images;
create policy "item images public read" on public.item_images for select using (true);
drop policy if exists "item images admin write" on public.item_images;
create policy "item images admin write" on public.item_images for all
to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "item variants public read" on public.item_variants;
create policy "item variants public read" on public.item_variants for select
using (is_active or public.is_admin());
drop policy if exists "item variants admin write" on public.item_variants;
create policy "item variants admin write" on public.item_variants for all
to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "inventory admin all" on public.inventory_units;
create policy "inventory admin all" on public.inventory_units for all
to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "price tiers public read" on public.item_price_tiers;
create policy "price tiers public read" on public.item_price_tiers for select using (true);
drop policy if exists "price tiers admin write" on public.item_price_tiers;
create policy "price tiers admin write" on public.item_price_tiers for all
to authenticated using (public.is_admin()) with check (public.is_admin());

grant select on public.item_categories, public.item_images, public.item_variants,
  public.item_price_tiers, public.item_inventory_summary to anon, authenticated;
grant select, insert, update, delete on public.item_categories, public.item_images,
  public.item_variants, public.inventory_units, public.item_price_tiers to authenticated;

-- Pastikan gambar utama lama ikut masuk ke galeri tanpa menggandakan data.
insert into public.item_images(item_id, image_url, alt_text, is_primary, sort_order)
select i.id, i.image_url, i.title, true, 0
from public.items i
where nullif(i.image_url, '') is not null
  and not exists (select 1 from public.item_images x where x.item_id = i.id);

-- Bucket publik untuk upload foto katalog dari admin panel.
insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('catalog', 'catalog', true, 8388608, array['image/jpeg','image/png','image/webp','image/gif'])
on conflict (id) do update set public = true;

drop policy if exists "catalog images public read" on storage.objects;
create policy "catalog images public read" on storage.objects for select
using (bucket_id = 'catalog');
drop policy if exists "catalog images admin insert" on storage.objects;
create policy "catalog images admin insert" on storage.objects for insert
to authenticated with check (bucket_id = 'catalog' and public.is_admin());
drop policy if exists "catalog images admin update" on storage.objects;
create policy "catalog images admin update" on storage.objects for update
to authenticated using (bucket_id = 'catalog' and public.is_admin());
drop policy if exists "catalog images admin delete" on storage.objects;
create policy "catalog images admin delete" on storage.objects for delete
to authenticated using (bucket_id = 'catalog' and public.is_admin());

-- ============================================================================
-- END SOURCE: catalog-management.sql
-- ============================================================================

-- ============================================================================
-- BEGIN SOURCE: voucher-management.sql
-- ============================================================================

-- Manajemen voucher AbidzarOutdoorcamp
-- Jalankan sekali melalui Supabase SQL Editor.

alter table public.vouchers
  add column if not exists applies_to text not null default 'all',
  add column if not exists once_per_customer boolean not null default false;

alter table public.vouchers drop constraint if exists vouchers_applies_to_check;
alter table public.vouchers add constraint vouchers_applies_to_check
  check (applies_to in ('all', 'rental', 'trip', 'products'));

create table if not exists public.voucher_items (
  voucher_id uuid not null references public.vouchers(id) on delete cascade,
  item_id uuid not null references public.items(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (voucher_id, item_id)
);

create table if not exists public.voucher_usages (
  id uuid primary key default gen_random_uuid(),
  voucher_id uuid not null references public.vouchers(id) on delete restrict,
  order_id uuid not null references public.orders(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  voucher_code text not null,
  discount numeric(14,2) not null default 0,
  status text not null default 'used' check (status in ('used', 'reversed')),
  used_at timestamptz not null default now(),
  reversed_at timestamptz,
  unique(order_id)
);

create index if not exists voucher_usages_voucher_used_idx
  on public.voucher_usages(voucher_id, used_at desc);
create index if not exists voucher_usages_user_idx
  on public.voucher_usages(user_id, used_at desc);

alter table public.voucher_items enable row level security;
alter table public.voucher_usages enable row level security;

drop policy if exists "voucher items admin all" on public.voucher_items;
create policy "voucher items admin all" on public.voucher_items
for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "voucher usages admin read" on public.voucher_usages;
create policy "voucher usages admin read" on public.voucher_usages
for select to authenticated using (public.is_admin());

drop policy if exists "voucher usages own read" on public.voucher_usages;
create policy "voucher usages own read" on public.voucher_usages
for select to authenticated using (user_id = auth.uid());

create or replace function public.voucher_scope_matches(
  p_voucher public.vouchers,
  p_items jsonb
) returns boolean
language sql stable security definer set search_path = public
as $$
  select case p_voucher.applies_to
    when 'all' then true
    when 'rental' then exists (
      select 1 from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) line
      join public.items i on i.id = (line->>'item_id')::uuid
      where i.type = 'product'
    )
    when 'trip' then exists (
      select 1 from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) line
      join public.items i on i.id = (line->>'item_id')::uuid
      where i.type = 'trip'
    )
    when 'products' then exists (
      select 1 from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) line
      join public.voucher_items vi
        on vi.voucher_id = p_voucher.id
       and vi.item_id = (line->>'item_id')::uuid
    )
    else false
  end;
$$;

drop function if exists public.preview_voucher(text, numeric);
drop function if exists public.preview_voucher(text, numeric, jsonb);
create function public.preview_voucher(
  p_code text,
  p_subtotal numeric,
  p_items jsonb default '[]'::jsonb
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v public.vouchers%rowtype;
  v_discount numeric := 0;
  v_code text := upper(trim(coalesce(p_code, '')));
begin
  if auth.uid() is null then raise exception 'Silakan login terlebih dahulu'; end if;
  if p_subtotal is null or p_subtotal < 0 then raise exception 'Subtotal tidak valid'; end if;

  select * into v from public.vouchers
  where code = v_code and is_active = true
    and now() between starts_at and expires_at
    and used_count < quota;
  if not found then raise exception 'Voucher tidak valid, belum aktif, berakhir, atau kuota habis'; end if;
  if p_subtotal < v.min_purchase then
    raise exception 'Minimal transaksi voucher adalah %', v.min_purchase;
  end if;
  if not public.voucher_scope_matches(v, p_items) then
    raise exception 'Voucher tidak berlaku untuk isi keranjang ini';
  end if;
  if v.once_per_customer and exists (
    select 1 from public.orders o
    where o.user_id = auth.uid() and o.voucher_code = v.code
      and o.status not in ('cancelled', 'failed', 'refunded')
  ) then raise exception 'Voucher hanya dapat digunakan satu kali per pelanggan'; end if;

  v_discount := case when v.discount_type = 'percent'
    then p_subtotal * (v.discount_value / 100) else v.discount_value end;
  if v.max_discount is not null then v_discount := least(v_discount, v.max_discount); end if;
  v_discount := least(v_discount, p_subtotal);

  return jsonb_build_object(
    'id', v.id, 'code', v.code, 'discount_type', v.discount_type,
    'discount_value', v.discount_value, 'discount', v_discount,
    'applies_to', v.applies_to, 'expires_at', v.expires_at
  );
end;
$$;
grant execute on function public.preview_voucher(text, numeric, jsonb) to authenticated;

create or replace function public.track_voucher_usage()
returns trigger language plpgsql security definer set search_path = public
as $$
declare v_id uuid;
begin
  if new.voucher_code is null then return new; end if;
  select id into v_id from public.vouchers where code = new.voucher_code;
  if v_id is null then return new; end if;

  if new.status in ('confirmed', 'paid', 'completed')
     and old.status not in ('confirmed', 'paid', 'completed') then
    insert into public.voucher_usages(
      voucher_id, order_id, user_id, voucher_code, discount, status
    ) values (v_id, new.id, new.user_id, new.voucher_code, new.discount, 'used')
    on conflict (order_id) do update set
      status = 'used', used_at = now(), reversed_at = null;
  elsif old.status in ('confirmed', 'paid', 'completed')
        and new.status in ('cancelled', 'failed', 'refunded') then
    update public.voucher_usages set status = 'reversed', reversed_at = now()
    where order_id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists orders_track_voucher_usage on public.orders;
create trigger orders_track_voucher_usage
after update of status on public.orders
for each row execute function public.track_voucher_usage();

grant select, insert, update, delete on public.vouchers to authenticated;
grant select, insert, update, delete on public.voucher_items to authenticated;
grant select on public.voucher_usages to authenticated;

-- ============================================================================
-- END SOURCE: voucher-management.sql
-- ============================================================================

-- ============================================================================
-- BEGIN SOURCE: open-trip-management.sql
-- ============================================================================

-- Jalankan sesudah catalog-management.sql dan sebelum rental-calendar.sql.
create table if not exists public.trip_details (
  item_id uuid primary key references public.items(id) on delete cascade,
  departure_at timestamptz,
  return_at timestamptz,
  meeting_point text,
  meeting_time text,
  itinerary text,
  included_facilities text,
  excluded_facilities text,
  difficulty text not null default 'moderate' check (difficulty in ('easy','moderate','hard','extreme')),
  min_age integer check (min_age is null or min_age >= 0),
  max_age integer check (max_age is null or max_age >= min_age),
  required_equipment text,
  min_participants integer not null default 1 check (min_participants > 0),
  registration_deadline timestamptz,
  status text not null default 'draft' check (status in ('draft','open','full','running','completed','cancelled')),
  travel_information text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.trip_participants (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  item_id uuid not null references public.items(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  seat_number integer not null check (seat_number > 0),
  full_name text not null,
  phone text not null,
  age integer not null check (age > 0),
  identity_last4 text,
  emergency_contact_name text not null,
  emergency_contact_phone text not null,
  notes text,
  status text not null default 'registered' check (status in ('registered','confirmed','cancelled','attended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (item_id, order_id, seat_number)
);

create index if not exists trip_participants_item_idx on public.trip_participants(item_id, status);
create index if not exists trip_participants_order_idx on public.trip_participants(order_id);

alter table public.trip_details enable row level security;
alter table public.trip_participants enable row level security;

drop policy if exists "trip details public read" on public.trip_details;
create policy "trip details public read" on public.trip_details for select using (true);
drop policy if exists "trip details admin write" on public.trip_details;
create policy "trip details admin write" on public.trip_details for all using (public.is_admin()) with check (public.is_admin());
drop policy if exists "participants own read" on public.trip_participants;
create policy "participants own read" on public.trip_participants for select using (auth.uid() = user_id or public.is_admin());
drop policy if exists "participants admin write" on public.trip_participants;
create policy "participants admin write" on public.trip_participants for all using (public.is_admin()) with check (public.is_admin());

insert into public.trip_details (item_id, departure_at, status)
select id, case when trip_date is null then null else trip_date::timestamp at time zone 'Asia/Jakarta' end,
       case when is_active then 'open' else 'draft' end
from public.items where type = 'trip'
on conflict (item_id) do nothing;

create or replace function public.admin_update_trip_participant_status(p_participant_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Akses ditolak'; end if;
  if p_status not in ('registered','confirmed','cancelled','attended') then raise exception 'Status tidak valid'; end if;
  update public.trip_participants set status = p_status, updated_at = now() where id = p_participant_id;
end; $$;
revoke all on function public.admin_update_trip_participant_status(uuid,text) from public;
grant execute on function public.admin_update_trip_participant_status(uuid,text) to authenticated;

-- ============================================================================
-- END SOURCE: open-trip-management.sql
-- ============================================================================

-- ============================================================================
-- BEGIN SOURCE: rental-calendar.sql
-- ============================================================================

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
      where item_id=v_item.id and duration_days=v_days
        and (variant_id=v_variant_id or variant_id is null)
      order by (variant_id=v_variant_id) desc limit 1;
      v_subtotal := v_subtotal + (
        (case when v_package_price is not null then v_package_price
          else v_item.price * v_days
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
      if nullif(v_line->>'trip_date','') is null then
        raise exception 'Tanggal perjalanan % wajib dipilih peserta', v_item.title;
      end if;
      if (v_line->>'trip_date')::date < current_date then
        raise exception 'Tanggal perjalanan % tidak boleh tanggal yang sudah lewat', v_item.title;
      end if;
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
      where item_id=v_item.id and duration_days=v_days
        and (variant_id=v_variant_id or variant_id is null)
      order by (variant_id=v_variant_id) desc limit 1;
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
          else v_item.price * v_days end
        else v_item.price end,
      v_quantity,
      (case when v_item.type = 'product' then
        case when v_package_price is not null then v_package_price
          else v_item.price * v_days end
        else v_item.price end) * v_quantity,
      case when v_item.type = 'trip' then (v_line->>'trip_date')::date else null end,
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

-- ============================================================================
-- END SOURCE: rental-calendar.sql
-- ============================================================================

-- ============================================================================
-- BEGIN SOURCE: btzpay-payment.sql
-- ============================================================================

-- AbidzarOutdoorcamp - Integrasi Pembayaran BTZPay
-- Jalankan setelah backup.txt, site-settings.sql, dan rental-calendar.sql.

alter table public.orders add column if not exists payment_status text not null default 'unpaid';
alter table public.orders add column if not exists paid_at timestamptz;

create table if not exists public.payment_transactions (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  gateway text not null default 'btzpay',
  gateway_transaction_id text not null unique,
  payment_method text not null,
  amount numeric(14,2) not null check (amount >= 0),
  total_amount numeric(14,2) not null check (total_amount >= 0),
  status text not null default 'pending'
    check (status in ('pending','paid','expired','cancelled','refunded','failed')),
  payment_url text,
  expires_at timestamptz,
  paid_at timestamptz,
  cancelled_at timestamptz,
  failure_reason text,
  last_checked_at timestamptz,
  raw_response jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Access key gateway dipisahkan agar tidak pernah dapat dibaca browser.
create table if not exists public.payment_gateway_secrets (
  payment_id uuid primary key references public.payment_transactions(id) on delete cascade,
  access_key text not null
);

create table if not exists public.payment_webhook_logs (
  id bigint generated always as identity primary key,
  gateway_transaction_id text,
  event_status text,
  payload jsonb not null default '{}'::jsonb,
  verified boolean not null default false,
  error_message text,
  created_at timestamptz not null default now()
);

create index if not exists payment_order_idx on public.payment_transactions(order_id, created_at desc);
create index if not exists payment_pending_expiry_idx on public.payment_transactions(expires_at)
  where status = 'pending';

alter table public.payment_transactions enable row level security;
alter table public.payment_gateway_secrets enable row level security;
alter table public.payment_webhook_logs enable row level security;

drop policy if exists "payment owner or admin read" on public.payment_transactions;
create policy "payment owner or admin read" on public.payment_transactions
for select to authenticated using (
  exists (select 1 from public.orders o where o.id = order_id and (o.user_id = auth.uid() or public.is_admin()))
);

drop policy if exists "payment logs admin read" on public.payment_webhook_logs;
create policy "payment logs admin read" on public.payment_webhook_logs
for select to authenticated using (public.is_admin());

revoke all on public.payment_transactions from anon, authenticated;
grant select on public.payment_transactions to authenticated;
revoke all on public.payment_gateway_secrets from anon, authenticated;
revoke all on public.payment_webhook_logs from anon, authenticated;
grant select on public.payment_webhook_logs to authenticated;
grant all on public.payment_transactions, public.payment_gateway_secrets, public.payment_webhook_logs to service_role;
grant usage, select on sequence public.payment_webhook_logs_id_seq to service_role;

create or replace function public.apply_btzpay_status(
  p_transaction_id text,
  p_status text,
  p_raw jsonb default '{}'::jsonb,
  p_reason text default null
)
returns void language plpgsql security definer set search_path = public
as $$
declare
  v_payment public.payment_transactions%rowtype;
  v_order public.orders%rowtype;
  v_line public.order_items%rowtype;
  v_status text;
  v_was_paid boolean;
  v_now_paid boolean;
begin
  if auth.role() <> 'service_role' then raise exception 'Service role diperlukan'; end if;

  v_status := case lower(coalesce(p_status, ''))
    when 'sukses' then 'paid' when 'paid' then 'paid'
    when 'expired' then 'expired'
    when 'cancel' then 'cancelled' when 'cancelled' then 'cancelled'
    when 'refunded' then 'refunded'
    when 'gagal' then 'failed' when 'failed' then 'failed'
    else 'pending' end;

  select * into v_payment from public.payment_transactions
  where gateway_transaction_id = p_transaction_id for update;
  if not found then raise exception 'Transaksi pembayaran tidak ditemukan'; end if;

  if v_payment.status in ('expired','cancelled','refunded','failed') and v_status = 'pending' then
    return;
  end if;
  if v_payment.status in ('expired','cancelled','refunded','failed') and v_status = 'paid' then
    raise exception 'Pembayaran diterima setelah transaksi ditutup; lakukan pemeriksaan dan refund manual';
  end if;

  select * into v_order from public.orders where id = v_payment.order_id for update;
  v_was_paid := v_payment.status = 'paid' or v_order.status in ('confirmed','paid','completed');
  v_now_paid := v_status = 'paid';

  if not v_was_paid and v_now_paid then
    for v_line in select * from public.order_items where order_id = v_order.id loop
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
  elsif v_was_paid and v_status in ('refunded','cancelled','expired','failed') then
    for v_line in select * from public.order_items where order_id = v_order.id loop
      if v_line.item_type = 'trip' then
        update public.items set quota = coalesce(quota, 0) + v_line.quantity where id = v_line.item_id;
      end if;
    end loop;
    if v_order.voucher_code is not null then
      update public.vouchers set used_count = greatest(used_count - 1, 0) where code = v_order.voucher_code;
    end if;
  end if;

  update public.payment_transactions set
    status = v_status,
    paid_at = case when v_status = 'paid' then coalesce(paid_at, now()) else paid_at end,
    cancelled_at = case when v_status in ('expired','cancelled','refunded','failed') then coalesce(cancelled_at, now()) else cancelled_at end,
    failure_reason = coalesce(nullif(p_reason, ''), failure_reason),
    last_checked_at = now(), raw_response = coalesce(p_raw, '{}'::jsonb), updated_at = now()
  where id = v_payment.id;

  update public.orders set
    payment_status = v_status,
    paid_at = case when v_status = 'paid' then coalesce(paid_at, now()) else paid_at end,
    status = case
      when v_status = 'paid' then 'paid'
      when v_status in ('expired','cancelled','failed') and status in ('pending','confirmed','paid') then 'cancelled'
      when v_status = 'refunded' then 'cancelled'
      else status end,
    updated_at = now()
  where id = v_order.id;
end;
$$;

revoke all on function public.apply_btzpay_status(text,text,jsonb,text) from public;
grant execute on function public.apply_btzpay_status(text,text,jsonb,text) to service_role;

-- ============================================================================
-- END SOURCE: btzpay-payment.sql
-- ============================================================================

-- ============================================================================
-- BEGIN SOURCE: order-management.sql
-- ============================================================================

-- AbidzarOutdoorcamp - Manajemen pesanan lanjutan
-- Jalankan setelah rental-calendar.sql dan btzpay-payment.sql.

alter table public.orders add column if not exists cancellation_reason text;
alter table public.orders add column if not exists cancelled_at timestamptz;
alter table public.orders add column if not exists late_fee numeric(14,2) not null default 0;
alter table public.orders add column if not exists deposit_amount numeric(14,2) not null default 0;
alter table public.orders add column if not exists deposit_status text not null default 'none'
  check (deposit_status in ('none','expected','received','partially_returned','returned','forfeited'));
alter table public.orders add column if not exists deposit_received_at timestamptz;
alter table public.orders add column if not exists deposit_returned_at timestamptz;
alter table public.orders add column if not exists returned_at timestamptz;
alter table public.orders add column if not exists return_condition text;
alter table public.orders add column if not exists inspection_notes text;

create table if not exists public.order_status_history (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.orders(id) on delete cascade,
  old_status text,
  new_status text not null,
  note text,
  changed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.order_refunds (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  payment_transaction_id uuid references public.payment_transactions(id) on delete set null,
  amount numeric(14,2) not null check (amount > 0),
  refund_type text not null check (refund_type in ('full','partial')),
  reason text not null,
  status text not null default 'recorded' check (status in ('recorded','processed','failed')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.order_returns (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  item_id uuid references public.items(id) on delete set null,
  quantity integer not null default 1 check (quantity > 0),
  condition text not null check (condition in ('good','dirty','damaged','lost')),
  fee numeric(14,2) not null default 0,
  notes text,
  inspected_by uuid references auth.users(id) on delete set null,
  inspected_at timestamptz not null default now()
);

create index if not exists order_history_order_idx on public.order_status_history(order_id, created_at desc);
create index if not exists order_refunds_order_idx on public.order_refunds(order_id, created_at desc);
create index if not exists order_returns_order_idx on public.order_returns(order_id, inspected_at desc);

alter table public.order_status_history enable row level security;
alter table public.order_refunds enable row level security;
alter table public.order_returns enable row level security;
drop policy if exists "order history admin read" on public.order_status_history;
create policy "order history admin read" on public.order_status_history for select using (public.is_admin());
drop policy if exists "refund admin read" on public.order_refunds;
create policy "refund admin read" on public.order_refunds for select using (public.is_admin());
drop policy if exists "return admin read" on public.order_returns;
create policy "return admin read" on public.order_returns for select using (public.is_admin());
grant select on public.order_status_history, public.order_refunds, public.order_returns to authenticated;

create or replace function public.log_order_status_change()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' or old.status is distinct from new.status then
    insert into public.order_status_history(order_id,old_status,new_status,note,changed_by)
    values (new.id,case when tg_op='INSERT' then null else old.status end,new.status,new.admin_notes,auth.uid());
  end if;
  return new;
end; $$;
drop trigger if exists orders_status_history_trigger on public.orders;
create trigger orders_status_history_trigger after insert or update of status on public.orders
for each row execute function public.log_order_status_change();

insert into public.order_status_history(order_id,old_status,new_status,note,created_at)
select o.id,null,o.status,'Riwayat awal',o.created_at from public.orders o
where not exists (select 1 from public.order_status_history h where h.order_id=o.id);

create or replace function public.admin_manage_order(
  p_order_id uuid,
  p_action text,
  p_amount numeric default null,
  p_reason text default null,
  p_condition text default null,
  p_item_id uuid default null,
  p_quantity integer default 1
) returns void language plpgsql security definer set search_path=public as $$
declare v_order public.orders%rowtype; v_payment_id uuid; v_refunded numeric;
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
    insert into public.order_returns(order_id,item_id,quantity,condition,fee,notes,inspected_by)
    values(p_order_id,p_item_id,greatest(coalesce(p_quantity,1),1),p_condition,greatest(coalesce(p_amount,0),0),nullif(trim(p_reason),''),auth.uid());
    update public.orders set returned_at=now(),return_condition=p_condition,inspection_notes=nullif(trim(p_reason),''),late_fee=late_fee+greatest(coalesce(p_amount,0),0) where id=p_order_id;
  else raise exception 'Aksi tidak dikenal'; end if;
end; $$;
revoke all on function public.admin_manage_order(uuid,text,numeric,text,text,uuid,integer) from public;
grant execute on function public.admin_manage_order(uuid,text,numeric,text,text,uuid,integer) to authenticated;

-- Meminta PostgREST/Supabase API membaca relasi tabel yang baru dibuat.
notify pgrst, 'reload schema';

-- ============================================================================
-- END SOURCE: order-management.sql
-- ============================================================================

-- ============================================================================
-- BEGIN SOURCE: customer-review-notification.sql
-- ============================================================================

-- AbidzarOutdoorcamp - Pelanggan, moderasi ulasan, dan notifikasi
-- Jalankan setelah backup.txt, rental-calendar.sql, dan order-management.sql.

alter table public.profiles add column if not exists is_verified boolean not null default false;
alter table public.profiles add column if not exists internal_notes text;
alter table public.profiles add column if not exists is_blocked boolean not null default false;
alter table public.profiles add column if not exists blocked_reason text;
alter table public.profiles add column if not exists blocked_at timestamptz;
alter table public.profiles add column if not exists created_at timestamptz not null default now();
alter table public.profiles add column if not exists updated_at timestamptz not null default now();
alter table public.profiles add column if not exists avatar_url text;

alter table public.website_ratings add column if not exists is_hidden boolean not null default false;
alter table public.website_ratings add column if not exists admin_reply text;
alter table public.website_ratings add column if not exists moderated_at timestamptz;
alter table public.website_ratings add column if not exists moderated_by uuid references auth.users(id) on delete set null;

create table if not exists public.customer_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  order_id uuid references public.orders(id) on delete cascade,
  notification_type text not null check (notification_type in ('order_created','payment_paid','payment_expired','order_confirmed','pickup_reminder','return_reminder','late_warning','trip_reminder','cancelled','refund','custom')),
  title text not null,
  message text not null,
  scheduled_for timestamptz not null default now(),
  status text not null default 'pending' check (status in ('pending','sent','cancelled')),
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  unique(order_id, notification_type)
);
create index if not exists customer_notifications_schedule_idx on public.customer_notifications(status, scheduled_for);
alter table public.customer_notifications enable row level security;
drop policy if exists "notifications admin read" on public.customer_notifications;
create policy "notifications admin read" on public.customer_notifications for select using (public.is_admin());
drop policy if exists "notifications own read" on public.customer_notifications;
create policy "notifications own read" on public.customer_notifications for select using (auth.uid()=user_id);
grant select on public.customer_notifications to authenticated;

create or replace function public.prevent_blocked_customer_order()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if exists(select 1 from public.profiles where id=new.user_id and is_blocked=true) then
    raise exception 'Akun Anda diblokir. Hubungi administrator.';
  end if;
  return new;
end; $$;
drop trigger if exists orders_prevent_blocked_customer on public.orders;
create trigger orders_prevent_blocked_customer before insert on public.orders for each row execute function public.prevent_blocked_customer_order();

create or replace function public.list_customer_summaries()
returns table(user_id uuid,email text,full_name text,phone text,city text,is_verified boolean,is_blocked boolean,blocked_reason text,internal_notes text,created_at timestamptz,total_orders bigint,total_spent numeric,cancelled_orders bigint,last_order_at timestamptz)
language plpgsql security definer set search_path=public,auth as $$
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  return query select p.id,u.email::text,p.full_name,p.phone,p.city,p.is_verified,p.is_blocked,p.blocked_reason,p.internal_notes,p.created_at,
    count(o.id),coalesce(sum(o.total) filter(where o.status not in ('cancelled')),0),count(o.id) filter(where o.status='cancelled'),max(o.created_at)
  from public.profiles p join auth.users u on u.id=p.id left join public.orders o on o.user_id=p.id
  where lower(trim(p.role)) <> 'admin'
  group by p.id,u.email,p.full_name,p.phone,p.city,p.is_verified,p.is_blocked,p.blocked_reason,p.internal_notes,p.created_at
  order by coalesce(sum(o.total) filter(where o.status not in ('cancelled')),0) desc;
end; $$;

create or replace function public.admin_update_customer(p_user_id uuid,p_verified boolean,p_blocked boolean,p_notes text default null,p_reason text default null)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  update public.profiles set is_verified=coalesce(p_verified,false),is_blocked=coalesce(p_blocked,false),internal_notes=nullif(trim(p_notes),''),blocked_reason=case when p_blocked then nullif(trim(p_reason),'') else null end,blocked_at=case when p_blocked then coalesce(blocked_at,now()) else null end,updated_at=now() where id=p_user_id;
  if not found then raise exception 'Pelanggan tidak ditemukan'; end if;
end; $$;

create or replace function public.list_admin_website_ratings()
returns table(id uuid,user_id uuid,email text,full_name text,score integer,comment text,is_hidden boolean,admin_reply text,created_at timestamptz,updated_at timestamptz)
language plpgsql security definer set search_path=public,auth as $$
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  return query select wr.id,wr.user_id,u.email::text,p.full_name,wr.score,wr.comment,wr.is_hidden,wr.admin_reply,wr.created_at,wr.updated_at from public.website_ratings wr join auth.users u on u.id=wr.user_id left join public.profiles p on p.id=wr.user_id order by wr.updated_at desc;
end; $$;

create or replace function public.admin_moderate_website_rating(p_rating_id uuid,p_hidden boolean,p_reply text default null)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  update public.website_ratings set is_hidden=coalesce(p_hidden,false),admin_reply=nullif(trim(p_reply),''),moderated_at=now(),moderated_by=auth.uid(),updated_at=now() where id=p_rating_id;
  if not found then raise exception 'Ulasan tidak ditemukan'; end if;
end; $$;

create or replace function public.queue_order_notification()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_type text; v_title text; v_message text;
begin
  if tg_op='INSERT' then v_type:='order_created'; v_title:='Pesanan dibuat'; v_message:='Pesanan '||new.order_number||' berhasil dibuat.';
  elsif old.payment_status is distinct from new.payment_status and new.payment_status='paid' then v_type:='payment_paid';v_title:='Pembayaran berhasil';v_message:='Pembayaran pesanan '||new.order_number||' telah diterima.';
  elsif old.payment_status is distinct from new.payment_status and new.payment_status='expired' then v_type:='payment_expired';v_title:='Pembayaran kedaluwarsa';v_message:='Pembayaran pesanan '||new.order_number||' telah kedaluwarsa.';
  elsif old.status is distinct from new.status and new.status='confirmed' then v_type:='order_confirmed';v_title:='Pesanan dikonfirmasi';v_message:='Pesanan '||new.order_number||' telah dikonfirmasi.';
  elsif old.status is distinct from new.status and new.status='cancelled' then v_type:='cancelled';v_title:='Pesanan dibatalkan';v_message:='Pesanan '||new.order_number||' dibatalkan.';
  elsif old.payment_status is distinct from new.payment_status and new.payment_status='refunded' then v_type:='refund';v_title:='Refund dicatat';v_message:='Refund pesanan '||new.order_number||' telah dicatat.';
  else return new; end if;
  insert into public.customer_notifications(user_id,order_id,notification_type,title,message,scheduled_for) values(new.user_id,new.id,v_type,v_title,v_message,now()) on conflict do nothing;
  return new;
end; $$;
drop trigger if exists orders_customer_notification_trigger on public.orders;
create trigger orders_customer_notification_trigger after insert or update of status,payment_status on public.orders for each row execute function public.queue_order_notification();

create or replace function public.admin_generate_reminders()
returns integer language plpgsql security definer set search_path=public as $$
declare v_count integer:=0; v_rows integer:=0;
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  insert into public.customer_notifications(user_id,order_id,notification_type,title,message,scheduled_for)
  select o.user_id,o.id,'pickup_reminder','Pengingat pengambilan','Pengambilan pesanan '||o.order_number||' dijadwalkan besok.',now() from public.orders o where o.rental_start=current_date+1 and o.status in ('confirmed','paid') on conflict do nothing; get diagnostics v_count=row_count;
  insert into public.customer_notifications(user_id,order_id,notification_type,title,message,scheduled_for)
  select o.user_id,o.id,'return_reminder','Pengingat pengembalian','Pengembalian pesanan '||o.order_number||' dijadwalkan besok.',now() from public.orders o where o.rental_end=current_date+1 and o.status in ('confirmed','paid') on conflict do nothing; get diagnostics v_rows=row_count; v_count:=v_count+v_rows;
  insert into public.customer_notifications(user_id,order_id,notification_type,title,message,scheduled_for)
  select o.user_id,o.id,'late_warning','Peringatan keterlambatan','Pesanan '||o.order_number||' melewati batas pengembalian.',now() from public.orders o where o.rental_end<current_date and o.returned_at is null and o.status in ('confirmed','paid') on conflict do nothing; get diagnostics v_rows=row_count; v_count:=v_count+v_rows;
  insert into public.customer_notifications(user_id,order_id,notification_type,title,message,scheduled_for)
  select distinct o.user_id,o.id,'trip_reminder','Trip segera berangkat','Open trip pada pesanan '||o.order_number||' berangkat dalam 2 hari.',now() from public.orders o join public.order_items oi on oi.order_id=o.id where oi.item_type='trip' and oi.trip_date_snapshot between current_date and current_date+2 and o.status in ('confirmed','paid') on conflict do nothing; get diagnostics v_rows=row_count; v_count:=v_count+v_rows;
  return v_count;
end; $$;

create or replace function public.admin_mark_notification_sent(p_notification_id uuid)
returns void language plpgsql security definer set search_path=public as $$ begin if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if; update public.customer_notifications set status='sent',sent_at=now() where id=p_notification_id; end; $$;

create or replace function public.get_website_rating()
returns jsonb language plpgsql stable security definer set search_path=public,auth as $$
declare v_average numeric:=0;v_count bigint:=0;v_my_score integer:=0;v_my_comment text:='';
begin
  select coalesce(round(avg(score)::numeric,1),0),count(*) into v_average,v_count from public.website_ratings where is_hidden=false;
  if auth.uid() is not null then select score,coalesce(comment,'') into v_my_score,v_my_comment from public.website_ratings where user_id=auth.uid() limit 1; end if;
  return jsonb_build_object('rating_average',v_average,'rating_count',v_count,'my_score',coalesce(v_my_score,0),'my_comment',coalesce(v_my_comment,''));
end; $$;

drop function if exists public.get_website_reviews(integer);
create function public.get_website_reviews(p_limit integer default 6)
returns table(display_name text,avatar_url text,score integer,comment text,created_at timestamptz,updated_at timestamptz,is_mine boolean,total_count bigint)
language sql stable security definer set search_path=public,auth as $$
with visible as (
  select case when nullif(trim(coalesce(p.full_name,'')),'') is not null then split_part(trim(p.full_name),' ',1) else 'Pengguna' end::text,
    p.avatar_url::text,
    wr.score,
    (coalesce(wr.comment,'')||case when nullif(trim(coalesce(wr.admin_reply,'')),'') is not null then E'\n\nBalasan admin: '||wr.admin_reply else '' end)::text,
    wr.created_at,wr.updated_at,(wr.user_id=auth.uid()),count(*) over()
  from public.website_ratings wr left join public.profiles p on p.id=wr.user_id
  where wr.is_hidden=false and nullif(trim(coalesce(wr.comment,'')),'') is not null
  order by case when wr.user_id=auth.uid() then 0 else 1 end,wr.updated_at desc
) select * from visible limit greatest(1,least(coalesce(p_limit,6),30));
$$;

revoke all on function public.list_customer_summaries() from public;
revoke all on function public.admin_update_customer(uuid,boolean,boolean,text,text) from public;
revoke all on function public.list_admin_website_ratings() from public;
revoke all on function public.admin_moderate_website_rating(uuid,boolean,text) from public;
revoke all on function public.admin_generate_reminders() from public;
revoke all on function public.admin_mark_notification_sent(uuid) from public;
grant execute on function public.list_customer_summaries() to authenticated;
grant execute on function public.admin_update_customer(uuid,boolean,boolean,text,text) to authenticated;
grant execute on function public.list_admin_website_ratings() to authenticated;
grant execute on function public.admin_moderate_website_rating(uuid,boolean,text) to authenticated;
grant execute on function public.admin_generate_reminders() to authenticated;
grant execute on function public.admin_mark_notification_sent(uuid) to authenticated;
grant execute on function public.get_website_rating() to anon, authenticated;
grant execute on function public.get_website_reviews(integer) to anon, authenticated;
notify pgrst, 'reload schema';

-- ============================================================================
-- END SOURCE: customer-review-notification.sql
-- ============================================================================

-- ============================================================================
-- BEGIN SOURCE: admin-management.sql
-- ============================================================================

-- AbidzarOutdoorcamp - Pengelolaan akun administrator
-- Jalankan setelah backup.txt.

-- Kompatibilitas untuk database versi lama.
alter table public.profiles
  add column if not exists created_at timestamptz not null default now();
alter table public.profiles
  add column if not exists updated_at timestamptz not null default now();

-- Versi lama mungkin memiliki susunan kolom return berbeda dan tidak dapat
-- diganti dengan CREATE OR REPLACE. Hapus signature lama lebih dulu.
drop function if exists public.list_admin_users();
drop function if exists public.add_admin_by_email(text, text);
drop function if exists public.remove_admin_access(uuid);

create or replace function public.list_admin_users()
returns table (
  user_id uuid,
  email text,
  full_name text,
  admin_since timestamptz,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  return query
  select p.id, u.email::text, p.full_name, p.updated_at, p.created_at
  from public.profiles p
  join auth.users u on u.id = p.id
  where lower(trim(p.role)) = 'admin'
  order by p.updated_at, u.email;
end;
$$;

create or replace function public.add_admin_by_email(
  p_email text,
  p_full_name text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id uuid;
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  select id into v_user_id from auth.users
  where lower(email) = lower(trim(p_email)) limit 1;
  if v_user_id is null then
    raise exception 'Akun dengan email tersebut belum terdaftar';
  end if;
  insert into public.profiles(id, full_name, role, updated_at)
  values(v_user_id, nullif(trim(p_full_name), ''), 'admin', now())
  on conflict(id) do update set
    full_name = coalesce(nullif(trim(p_full_name), ''), public.profiles.full_name),
    role = 'admin', updated_at = now();
  return v_user_id;
end;
$$;

create or replace function public.remove_admin_access(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  if p_user_id = auth.uid() then raise exception 'Anda tidak dapat mencabut akses akun sendiri'; end if;
  if (select count(*) from public.profiles where lower(trim(role))='admin') <= 1 then
    raise exception 'Minimal satu administrator harus tetap aktif';
  end if;
  update public.profiles set role='user', updated_at=now()
  where id=p_user_id and lower(trim(role))='admin';
  if not found then raise exception 'Administrator tidak ditemukan'; end if;
end;
$$;

revoke all on function public.list_admin_users() from public;
revoke all on function public.add_admin_by_email(text,text) from public;
revoke all on function public.remove_admin_access(uuid) from public;
grant execute on function public.list_admin_users() to authenticated;
grant execute on function public.add_admin_by_email(text,text) to authenticated;
grant execute on function public.remove_admin_access(uuid) to authenticated;

-- ============================================================================
-- END SOURCE: admin-management.sql
-- ============================================================================

-- ============================================================================
-- BEGIN SOURCE: stock-lifecycle.sql
-- ============================================================================

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
        if v_line.variant_id is not null then
          update public.item_variants set stock=stock-v_line.quantity
          where id=v_line.variant_id and item_id=v_line.item_id and stock>=v_line.quantity;
        else
          update public.items set stock=stock-v_line.quantity
          where id=v_line.item_id and stock>=v_line.quantity;
        end if;

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
        if v_line.variant_id is not null then
          update public.item_variants set stock=stock+v_outstanding where id=v_line.variant_id;
        else
          update public.items set stock=stock+v_outstanding where id=v_line.item_id;
        end if;
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
    if v_line.variant_id is not null then
      update public.item_variants set stock=stock+v_line.quantity where id=v_line.variant_id;
    else
      update public.items set stock=stock+v_line.quantity where id=v_line.item_id;
    end if;
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
    if v_line.variant_id is not null then
      update public.item_variants set stock=stock-v_line.quantity
      where id=v_line.variant_id and stock>=v_line.quantity;
    else
      update public.items set stock=stock-v_line.quantity
      where id=v_line.item_id and stock>=v_line.quantity;
    end if;
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

-- ============================================================================
-- END SOURCE: stock-lifecycle.sql
-- ============================================================================

-- ============================================================================
-- BEGIN SOURCE: fix-rental-price-constraint.sql
-- ============================================================================

-- Perbaikan error:
-- new row for relation "order_items" violates check constraint
-- "order_items_rental_total_check"

alter table public.order_items
  drop constraint if exists order_items_rental_total_check;

-- Pesanan lama menyimpan harga harian. Ubah snapshot menjadi harga satu unit
-- untuk seluruh periode tanpa mengubah line_total maupun total pesanan.
update public.order_items
set price_snapshot = line_total / quantity
where quantity > 0
  and line_total is distinct from price_snapshot * quantity;

alter table public.order_items
  add constraint order_items_rental_total_check
  check (line_total = price_snapshot * quantity);

notify pgrst, 'reload schema';

-- ============================================================================
-- END SOURCE: fix-rental-price-constraint.sql
-- ============================================================================

-- ============================================================================
-- BEGIN SOURCE: order-cleanup.sql
-- ============================================================================

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
  update public.item_variants v
  set stock=v.stock+restore.quantity
  from (
    select oi.variant_id,sum(oi.quantity)::integer quantity
    from public.order_items oi join public.orders o on o.id=oi.order_id
    where o.status='cancelled' and oi.item_type='product'
      and oi.variant_id is not null and coalesce(oi.stock_deducted,false)
    group by oi.variant_id
  ) restore where v.id=restore.variant_id;

  update public.items i
  set stock = i.stock + restore.quantity
  from (
    select oi.item_id, sum(oi.quantity)::integer as quantity
    from public.order_items oi
    join public.orders o on o.id=oi.order_id
    where o.status='cancelled'
      and oi.item_type='product'
      and oi.variant_id is null and coalesce(oi.stock_deducted,false)
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
  update public.item_variants v
  set stock=v.stock+restore.quantity
  from (
    select oi.variant_id,sum(oi.quantity)::integer quantity
    from public.order_items oi
    where oi.item_type='product' and oi.variant_id is not null
      and coalesce(oi.stock_deducted,false)
    group by oi.variant_id
  ) restore where v.id=restore.variant_id;

  update public.items i
  set stock = i.stock + restore.quantity
  from (
    select oi.item_id, sum(oi.quantity)::integer as quantity
    from public.order_items oi
    where oi.item_type='product' and oi.variant_id is null and coalesce(oi.stock_deducted,false)
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

  -- Supabase Safe Update mewajibkan klausa WHERE pada operasi DELETE.
  delete from public.voucher_usages where id is not null;
  delete from public.orders where id is not null;

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

-- ============================================================================
-- END SOURCE: order-cleanup.sql
-- ============================================================================

-- ============================================================================
-- BEGIN SOURCE: preserve-rating-comment.sql
-- ============================================================================

-- PERBAIKAN KOMENTAR RATING WEBSITE
-- Kolom komentar kosong tidak lagi menghapus komentar lama.
-- Jalankan seluruh file ini melalui Supabase SQL Editor.

create or replace function public.submit_website_rating(
  p_score integer,
  p_comment text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_input_comment text;
  v_saved_comment text;
  v_average numeric := 0;
  v_count bigint := 0;
begin
  if v_user_id is null then
    raise exception 'Silakan login untuk memberikan rating website';
  end if;

  if p_score is null or p_score < 1 or p_score > 5 then
    raise exception 'Rating harus antara 1 sampai 5 bintang';
  end if;

  v_input_comment := nullif(trim(coalesce(p_comment, '')), '');

  if v_input_comment is not null
     and char_length(v_input_comment) > 300 then
    raise exception 'Komentar maksimal 300 karakter';
  end if;

  select wr.comment
  into v_saved_comment
  from public.website_ratings wr
  where wr.user_id = v_user_id
  limit 1;

  -- Input kosong mempertahankan komentar sebelumnya.
  v_saved_comment := coalesce(v_input_comment, v_saved_comment);

  insert into public.website_ratings (
    user_id,
    score,
    comment,
    updated_at
  )
  values (
    v_user_id,
    p_score,
    v_saved_comment,
    now()
  )
  on conflict (user_id)
  do update set
    score = excluded.score,
    comment = coalesce(
      excluded.comment,
      public.website_ratings.comment
    ),
    updated_at = now();

  select wr.comment
  into v_saved_comment
  from public.website_ratings wr
  where wr.user_id = v_user_id
  limit 1;

  select
    coalesce(round(avg(wr.score)::numeric, 1), 0),
    count(*)
  into
    v_average,
    v_count
  from public.website_ratings wr;

  return jsonb_build_object(
    'rating_average', v_average,
    'rating_count', v_count,
    'my_score', p_score,
    'my_comment', coalesce(v_saved_comment, '')
  );
end;
$$;

revoke all on function public.submit_website_rating(integer, text)
from public;

grant execute on function public.submit_website_rating(integer, text)
to authenticated;

notify pgrst, 'reload schema';

select
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as arguments
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'submit_website_rating';

-- ============================================================================
-- END SOURCE: preserve-rating-comment.sql
-- ============================================================================

-- ============================================================================
-- BEGIN SOURCE: website-comment-rpc-v2.sql
-- ============================================================================

-- PERBAIKAN RATING DAN KOMENTAR WEBSITE
-- Jalankan seluruh file ini di Supabase SQL Editor.

alter table public.website_ratings
  add column if not exists comment text;
alter table public.website_ratings
  add column if not exists is_hidden boolean not null default false;

create unique index if not exists website_ratings_user_unique
  on public.website_ratings(user_id);

create or replace function public.save_website_review_v2(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_score integer;
  v_input_comment text;
  v_existing_comment text;
  v_saved_comment text;
  v_average numeric := 0;
  v_count bigint := 0;
begin
  if v_user_id is null then
    raise exception 'Silakan login untuk memberikan rating website';
  end if;

  begin
    v_score := (p_payload ->> 'score')::integer;
  exception
    when others then
      raise exception 'Nilai rating tidak valid';
  end;

  if v_score is null or v_score < 1 or v_score > 5 then
    raise exception 'Rating harus antara 1 sampai 5 bintang';
  end if;

  v_input_comment :=
    nullif(trim(coalesce(p_payload ->> 'comment', '')), '');

  if v_input_comment is not null
     and char_length(v_input_comment) > 300 then
    raise exception 'Komentar maksimal 300 karakter';
  end if;

  select wr.comment
    into v_existing_comment
  from public.website_ratings wr
  where wr.user_id = v_user_id
  limit 1;

  if v_input_comment is null and v_existing_comment is null then
    raise exception 'Komentar wajib diisi agar ulasan dapat ditampilkan';
  end if;

  -- Jika input komentar kosong, komentar lama tidak dihapus.
  v_saved_comment := coalesce(v_input_comment, v_existing_comment);

  insert into public.website_ratings (
    user_id,
    score,
    comment,
    created_at,
    updated_at
  )
  values (
    v_user_id,
    v_score,
    v_saved_comment,
    now(),
    now()
  )
  on conflict (user_id)
  do update set
    score = excluded.score,
    comment = coalesce(
      excluded.comment,
      public.website_ratings.comment
    ),
    updated_at = now();

  select wr.comment
    into v_saved_comment
  from public.website_ratings wr
  where wr.user_id = v_user_id
  limit 1;

  select
    coalesce(round(avg(wr.score)::numeric, 1), 0),
    count(*)
  into v_average, v_count
  from public.website_ratings wr
  where coalesce(wr.is_hidden, false) = false;

  return jsonb_build_object(
    'success', true,
    'rating_average', v_average,
    'rating_count', v_count,
    'my_score', v_score,
    'my_comment', coalesce(v_saved_comment, '')
  );
end;
$$;

create or replace function public.submit_website_rating(
  p_score integer,
  p_comment text default null
)
returns jsonb
language sql
security definer
set search_path = public, auth
as $$
  select public.save_website_review_v2(
    jsonb_build_object(
      'score', p_score,
      'comment', p_comment
    )
  );
$$;

revoke all on function public.save_website_review_v2(jsonb) from public;
revoke all on function public.submit_website_rating(integer, text) from public;
grant execute on function public.save_website_review_v2(jsonb) to authenticated;
grant execute on function public.submit_website_rating(integer, text) to authenticated;

notify pgrst, 'reload schema';

-- Pemeriksaan: comment seharusnya berisi teks, bukan NULL,
-- setelah pengguna mengirim rating dan komentar lagi.
select user_id, score, comment, is_hidden, updated_at
from public.website_ratings
order by updated_at desc;

-- ============================================================================
-- END SOURCE: website-comment-rpc-v2.sql
-- ============================================================================

-- ============================================================================
-- BEGIN SOURCE: profile-avatar.sql
-- ============================================================================

-- FOTO PROFIL PENGGUNA DAN AVATAR ULASAN
-- Jalankan seluruh file ini melalui Supabase SQL Editor.

alter table public.profiles
  add column if not exists avatar_url text;

grant select on public.profiles to authenticated;
grant update(avatar_url) on public.profiles to authenticated;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'avatars',
  'avatars',
  true,
  3145728,
  array['image/jpeg','image/png','image/webp']
)
on conflict (id) do update set
  public = true,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "avatars public read" on storage.objects;
create policy "avatars public read"
on storage.objects for select
using (bucket_id = 'avatars');

drop policy if exists "users upload own avatar" on storage.objects;
create policy "users upload own avatar"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "users update own avatar" on storage.objects;
create policy "users update own avatar"
on storage.objects for update
to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "users delete own avatar" on storage.objects;
create policy "users delete own avatar"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- Return type bertambah avatar_url, sehingga fungsi lama harus dihapus dahulu.
drop function if exists public.get_website_reviews(integer);

create function public.get_website_reviews(p_limit integer default 6)
returns table(
  display_name text,
  avatar_url text,
  score integer,
  comment text,
  created_at timestamptz,
  updated_at timestamptz,
  is_mine boolean,
  total_count bigint
)
language sql
stable
security definer
set search_path = public, auth
as $$
  with visible as (
    select
      case
        when nullif(trim(coalesce(p.full_name, '')), '') is not null
          then split_part(trim(p.full_name), ' ', 1)
        else 'Pengguna'
      end::text as display_name,
      p.avatar_url::text,
      wr.score,
      (
        coalesce(wr.comment, '') ||
        case
          when nullif(trim(coalesce(wr.admin_reply, '')), '') is not null
            then E'\n\nBalasan admin: ' || wr.admin_reply
          else ''
        end
      )::text as comment,
      wr.created_at,
      wr.updated_at,
      (wr.user_id = auth.uid()) as is_mine,
      count(*) over() as total_count
    from public.website_ratings wr
    left join public.profiles p on p.id = wr.user_id
    where coalesce(wr.is_hidden, false) = false
      and nullif(trim(coalesce(wr.comment, '')), '') is not null
    order by
      case when wr.user_id = auth.uid() then 0 else 1 end,
      wr.updated_at desc
  )
  select *
  from visible
  limit greatest(1, least(coalesce(p_limit, 6), 30));
$$;

revoke all on function public.get_website_reviews(integer) from public;
grant execute on function public.get_website_reviews(integer)
  to anon, authenticated;

notify pgrst, 'reload schema';

-- ============================================================================
-- END SOURCE: profile-avatar.sql
-- ============================================================================

-- ============================================================================
-- BEGIN SOURCE: access-security.sql
-- ============================================================================

-- AbidzarOutdoorcamp - Hak akses bertingkat, RLS, dan audit log
-- Jalankan PALING AKHIR setelah seluruh file SQL fitur lainnya.

do $$ declare c record; begin
  for c in select conname from pg_constraint where conrelid='public.profiles'::regclass and contype='c' and pg_get_constraintdef(oid) ilike '%role%'
  loop execute format('alter table public.profiles drop constraint %I',c.conname); end loop;
end $$;
update public.profiles set role=lower(trim(role));
update public.profiles set role='super_admin' where role='admin';
update public.profiles set role='user' where role not in ('user','super_admin','order_admin','catalog_admin','finance_admin','warehouse_staff');
alter table public.profiles add constraint profiles_role_access_check check(role in ('user','super_admin','order_admin','catalog_admin','finance_admin','warehouse_staff'));

create table if not exists public.role_permissions(role text not null,permission text not null,primary key(role,permission));
insert into public.role_permissions(role,permission) values
('super_admin','*'),('order_admin','orders.view'),('order_admin','orders.manage'),('order_admin','customers.view'),('order_admin','customers.manage'),('order_admin','notifications.manage'),('order_admin','reviews.manage'),('order_admin','trip_participants.manage'),
('catalog_admin','catalog.manage'),('catalog_admin','settings.manage'),('catalog_admin','reviews.manage'),
('finance_admin','orders.view'),('finance_admin','finance.manage'),('finance_admin','vouchers.manage'),('finance_admin','reports.view'),
('warehouse_staff','orders.view'),('warehouse_staff','warehouse.manage'),('warehouse_staff','trip_participants.manage')
on conflict do nothing;

create or replace function public.has_permission(p_permission text) returns boolean language sql stable security definer set search_path=public as $$
select exists(select 1 from public.profiles p join public.role_permissions rp on rp.role=p.role where p.id=auth.uid() and (rp.permission='*' or rp.permission=p_permission)); $$;
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$ select public.has_permission('*') or exists(select 1 from public.profiles where id=auth.uid() and role in ('order_admin','catalog_admin','finance_admin','warehouse_staff')); $$;
create or replace function public.get_my_staff_permissions() returns jsonb language sql stable security definer set search_path=public as $$
select jsonb_build_object('role',coalesce(p.role,'user'),'permissions',coalesce((select jsonb_agg(permission) from public.role_permissions where role=p.role),'[]'::jsonb)) from public.profiles p where p.id=auth.uid(); $$;

create table if not exists public.admin_activity_logs(
 id bigint generated always as identity primary key,admin_user_id uuid references auth.users(id) on delete set null,admin_role text,action text not null,table_name text not null,record_id text,old_data jsonb,new_data jsonb,created_at timestamptz not null default now()
);
alter table public.admin_activity_logs enable row level security;
create or replace function public.audit_admin_change() returns trigger language plpgsql security definer set search_path=public as $$
declare v_role text;v_old jsonb;v_new jsonb;v_id text;
begin select role into v_role from public.profiles where id=auth.uid(); if v_role is null or v_role='user' then return coalesce(new,old); end if;
v_old:=case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end;v_new:=case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end;v_id:=coalesce(v_new->>'id',v_old->>'id',v_new->>'order_id',v_old->>'order_id');
insert into public.admin_activity_logs(admin_user_id,admin_role,action,table_name,record_id,old_data,new_data) values(auth.uid(),v_role,lower(tg_op),tg_table_name,v_id,v_old,v_new);return coalesce(new,old);end; $$;
do $$ declare t text; begin foreach t in array array['items','item_categories','item_images','item_variants','inventory_units','item_price_tiers','trip_details','trip_participants','orders','vouchers','voucher_items','site_settings','website_ratings','customer_notifications','order_refunds','order_returns','profiles'] loop if to_regclass('public.'||t) is not null then execute format('drop trigger if exists audit_admin_change_trigger on public.%I',t);execute format('create trigger audit_admin_change_trigger after insert or update or delete on public.%I for each row execute function public.audit_admin_change()',t);end if;end loop;end $$;

-- Tutup RPC admin lama; frontend memakai wrapper aman di bawah.
revoke execute on function public.admin_update_order_status(uuid,text,text) from authenticated;
revoke execute on function public.admin_manage_order(uuid,text,numeric,text,text,uuid,integer) from authenticated;
revoke execute on function public.admin_update_customer(uuid,boolean,boolean,text,text) from authenticated;
revoke execute on function public.admin_moderate_website_rating(uuid,boolean,text) from authenticated;
revoke execute on function public.admin_generate_reminders() from authenticated;
revoke execute on function public.admin_mark_notification_sent(uuid) from authenticated;
revoke execute on function public.admin_update_trip_participant_status(uuid,text) from authenticated;
revoke execute on function public.list_customer_summaries() from authenticated;
revoke execute on function public.list_admin_website_ratings() from authenticated;
revoke execute on function public.list_admin_users() from authenticated;
revoke execute on function public.add_admin_by_email(text,text) from authenticated;
revoke execute on function public.remove_admin_access(uuid) from authenticated;
revoke execute on function public.admin_save_site_settings(jsonb) from authenticated;

create or replace function public.secure_admin_save_site_settings(p_settings jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_settings jsonb;
begin
  if not (public.has_permission('settings.manage') or public.has_permission('*')) then
    raise exception 'Izin pengaturan website diperlukan';
  end if;
  if p_settings is null or jsonb_typeof(p_settings)<>'object' then
    raise exception 'Format pengaturan tidak valid';
  end if;
  v_settings := p_settings || jsonb_build_object(
    'whatsapp_number',regexp_replace(coalesce(p_settings->>'whatsapp_number',''),'[^0-9]','','g'),
    'admin_1_whatsapp',regexp_replace(coalesce(p_settings->>'admin_1_whatsapp',''),'[^0-9]','','g'),
    'admin_2_whatsapp',regexp_replace(coalesce(p_settings->>'admin_2_whatsapp',''),'[^0-9]','','g'),
    'admin_3_whatsapp',regexp_replace(coalesce(p_settings->>'admin_3_whatsapp',''),'[^0-9]','','g')
  );
  insert into public.site_settings(id,settings,updated_at,updated_by)
  values('main',v_settings,now(),auth.uid())
  on conflict(id) do update set settings=excluded.settings,
    updated_at=excluded.updated_at,updated_by=excluded.updated_by;
  return v_settings;
end$$;
revoke all on function public.secure_admin_save_site_settings(jsonb) from public;
grant execute on function public.secure_admin_save_site_settings(jsonb) to authenticated;

create or replace function public.secure_admin_update_order_status(a uuid,b text,c text default null) returns void language plpgsql security definer set search_path=public as $$begin if not public.has_permission('orders.manage') then raise exception 'Izin pesanan diperlukan';end if;perform public.admin_update_order_status(a,b,c);end$$;
create or replace function public.secure_admin_manage_order(a uuid,b text,c numeric default null,d text default null,e text default null,f uuid default null,g integer default 1) returns void language plpgsql security definer set search_path=public as $$begin if (b='refund' and not public.has_permission('finance.manage')) or (b='cancel' and not public.has_permission('orders.manage')) or (b='return' and not public.has_permission('warehouse.manage')) or (b in('deposit_received','deposit_returned') and not(public.has_permission('finance.manage') or public.has_permission('warehouse.manage'))) or (b='late_fee' and not(public.has_permission('orders.manage') or public.has_permission('warehouse.manage'))) then raise exception 'Izin operasional diperlukan';end if;perform public.admin_manage_order(a,b,c,d,e,f,g);end$$;
create or replace function public.secure_admin_update_customer(a uuid,b boolean,c boolean,d text default null,e text default null) returns void language plpgsql security definer set search_path=public as $$begin if not public.has_permission('customers.manage') then raise exception 'Izin pelanggan diperlukan';end if;perform public.admin_update_customer(a,b,c,d,e);end$$;
create or replace function public.secure_admin_moderate_rating(a uuid,b boolean,c text default null) returns void language plpgsql security definer set search_path=public as $$begin if not public.has_permission('reviews.manage') then raise exception 'Izin moderasi diperlukan';end if;perform public.admin_moderate_website_rating(a,b,c);end$$;
create or replace function public.secure_admin_generate_reminders() returns integer language plpgsql security definer set search_path=public as $$begin if not public.has_permission('notifications.manage') then raise exception 'Izin notifikasi diperlukan';end if;return public.admin_generate_reminders();end$$;
create or replace function public.secure_admin_mark_notification_sent(a uuid) returns void language plpgsql security definer set search_path=public as $$begin if not public.has_permission('notifications.manage') then raise exception 'Izin notifikasi diperlukan';end if;perform public.admin_mark_notification_sent(a);end$$;
create or replace function public.secure_admin_update_participant_status(a uuid,b text) returns void language plpgsql security definer set search_path=public as $$begin if not public.has_permission('trip_participants.manage') then raise exception 'Izin peserta diperlukan';end if;perform public.admin_update_trip_participant_status(a,b);end$$;
create or replace function public.secure_list_customers() returns table(user_id uuid,email text,full_name text,phone text,city text,is_verified boolean,is_blocked boolean,blocked_reason text,internal_notes text,created_at timestamptz,total_orders bigint,total_spent numeric,cancelled_orders bigint,last_order_at timestamptz) language plpgsql security definer set search_path=public as $$begin if not public.has_permission('customers.view') then raise exception 'Izin pelanggan diperlukan';end if;return query select * from public.list_customer_summaries();end$$;
create or replace function public.secure_list_ratings() returns table(id uuid,user_id uuid,email text,full_name text,score integer,comment text,is_hidden boolean,admin_reply text,created_at timestamptz,updated_at timestamptz) language plpgsql security definer set search_path=public as $$begin if not public.has_permission('reviews.manage') then raise exception 'Izin moderasi diperlukan';end if;return query select * from public.list_admin_website_ratings();end$$;
create or replace function public.secure_list_admin_users() returns table(user_id uuid,email text,full_name text,admin_since timestamptz,created_at timestamptz) language plpgsql security definer set search_path=public as $$begin if not public.has_permission('*') then raise exception 'Izin super admin diperlukan';end if;return query select * from public.list_admin_users();end$$;
create or replace function public.secure_add_admin_by_email(a text,b text default null) returns uuid language plpgsql security definer set search_path=public as $$begin if not public.has_permission('*') then raise exception 'Izin super admin diperlukan';end if;return public.add_admin_by_email(a,b);end$$;
create or replace function public.secure_remove_admin_access(a uuid) returns void language plpgsql security definer set search_path=public as $$begin if not public.has_permission('*') then raise exception 'Izin super admin diperlukan';end if;perform public.remove_admin_access(a);end$$;
create or replace function public.secure_list_staff_users() returns table(user_id uuid,email text,full_name text,role text,created_at timestamptz) language plpgsql security definer set search_path=public,auth as $$begin if not public.has_permission('*') then raise exception 'Izin super admin diperlukan';end if;return query select p.id,u.email::text,p.full_name,p.role,p.created_at from public.profiles p join auth.users u on u.id=p.id where p.role<>'user' order by p.created_at;end$$;
create or replace function public.secure_set_staff_role(a text,b text,c text default null) returns uuid language plpgsql security definer set search_path=public,auth as $$declare v_id uuid;begin if not public.has_permission('*') then raise exception 'Izin super admin diperlukan';end if;if b not in('super_admin','order_admin','catalog_admin','finance_admin','warehouse_staff') then raise exception 'Role tidak valid';end if;select id into v_id from auth.users where lower(email)=lower(trim(a)) limit 1;if v_id is null then raise exception 'Akun belum terdaftar';end if;if b<>'super_admin' and exists(select 1 from public.profiles where id=v_id and role='super_admin') and (select count(*) from public.profiles where role='super_admin')<=1 then raise exception 'Minimal satu Super Admin harus aktif';end if;insert into public.profiles(id,full_name,role,updated_at) values(v_id,nullif(trim(c),''),b,now()) on conflict(id) do update set full_name=coalesce(nullif(trim(c),''),public.profiles.full_name),role=b,updated_at=now();return v_id;end$$;
create or replace function public.secure_remove_staff_role(a uuid) returns void language plpgsql security definer set search_path=public as $$begin if not public.has_permission('*') then raise exception 'Izin super admin diperlukan';end if;if a=auth.uid() then raise exception 'Tidak dapat mencabut role akun sendiri';end if;if exists(select 1 from public.profiles where id=a and role='super_admin') and (select count(*) from public.profiles where role='super_admin')<=1 then raise exception 'Minimal satu Super Admin harus aktif';end if;update public.profiles set role='user',updated_at=now() where id=a;if not found then raise exception 'Petugas tidak ditemukan';end if;end$$;

grant execute on function public.has_permission(text),public.is_admin(),public.get_my_staff_permissions() to authenticated;
grant execute on function public.secure_admin_update_order_status(uuid,text,text),public.secure_admin_manage_order(uuid,text,numeric,text,text,uuid,integer),public.secure_admin_update_customer(uuid,boolean,boolean,text,text),public.secure_admin_moderate_rating(uuid,boolean,text),public.secure_admin_generate_reminders(),public.secure_admin_mark_notification_sent(uuid),public.secure_admin_update_participant_status(uuid,text),public.secure_list_customers(),public.secure_list_ratings(),public.secure_list_admin_users(),public.secure_add_admin_by_email(text,text),public.secure_remove_admin_access(uuid),public.secure_list_staff_users(),public.secure_set_staff_role(text,text,text),public.secure_remove_staff_role(uuid) to authenticated;

-- RLS: hapus policy lama pada tabel sensitif lalu buat aturan berbasis izin.
do $$ declare t text;p record;begin foreach t in array array['profiles','items','item_categories','item_images','item_variants','inventory_units','item_price_tiers','orders','order_items','vouchers','voucher_items','voucher_usages','site_settings','trip_details','trip_participants','payment_transactions','payment_webhook_logs','customer_notifications','order_status_history','order_refunds','order_returns','admin_activity_logs'] loop if to_regclass('public.'||t) is not null then for p in select policyname from pg_policies where schemaname='public' and tablename=t loop execute format('drop policy %I on public.%I',p.policyname,t);end loop;end if;end loop;end$$;
create policy profiles_read on public.profiles for select using(id=auth.uid() or public.has_permission('customers.view') or public.has_permission('*'));
create policy profiles_own_update on public.profiles for update using(id=auth.uid()) with check(id=auth.uid());
create policy items_public_read on public.items for select using(is_active=true or public.has_permission('catalog.manage') or public.has_permission('*'));
create policy items_catalog_write on public.items for all using(public.has_permission('catalog.manage') or public.has_permission('*')) with check(public.has_permission('catalog.manage') or public.has_permission('*'));
create policy orders_read on public.orders for select using(user_id=auth.uid() or public.has_permission('orders.view') or public.has_permission('*'));
create policy order_items_read on public.order_items for select using(exists(select 1 from public.orders o where o.id=order_id and (o.user_id=auth.uid() or public.has_permission('orders.view') or public.has_permission('*'))));
create policy vouchers_staff on public.vouchers for all using(public.has_permission('vouchers.manage') or public.has_permission('*')) with check(public.has_permission('vouchers.manage') or public.has_permission('*'));
create policy settings_read on public.site_settings for select using(true);create policy settings_write on public.site_settings for all using(public.has_permission('settings.manage') or public.has_permission('*')) with check(public.has_permission('settings.manage') or public.has_permission('*'));
create policy audit_super_read on public.admin_activity_logs for select using(public.has_permission('*'));

-- Policies generik untuk tabel katalog dan operasional yang tersedia.
do $$ declare t text;begin foreach t in array array['item_categories','item_images','item_variants','item_price_tiers','trip_details'] loop if to_regclass('public.'||t) is not null then execute format('create policy public_read on public.%I for select using(true)',t);execute format('create policy catalog_write on public.%I for all using(public.has_permission(''catalog.manage'') or public.has_permission(''*'')) with check(public.has_permission(''catalog.manage'') or public.has_permission(''*''))',t);end if;end loop;end$$;
create policy inventory_staff on public.inventory_units for all using(public.has_permission('warehouse.manage') or public.has_permission('catalog.manage') or public.has_permission('*')) with check(public.has_permission('warehouse.manage') or public.has_permission('catalog.manage') or public.has_permission('*'));
create policy participants_read on public.trip_participants for select using(user_id=auth.uid() or public.has_permission('trip_participants.manage') or public.has_permission('*'));
create policy payments_read on public.payment_transactions for select using(exists(select 1 from public.orders o where o.id=order_id and o.user_id=auth.uid()) or public.has_permission('finance.manage') or public.has_permission('*'));
create policy payment_logs_finance on public.payment_webhook_logs for select using(public.has_permission('finance.manage') or public.has_permission('*'));
create policy notifications_read on public.customer_notifications for select using(user_id=auth.uid() or public.has_permission('notifications.manage') or public.has_permission('*'));
create policy history_staff on public.order_status_history for select using(public.has_permission('orders.view') or public.has_permission('*'));
create policy refunds_staff on public.order_refunds for select using(public.has_permission('finance.manage') or public.has_permission('orders.manage') or public.has_permission('*'));
create policy returns_staff on public.order_returns for select using(public.has_permission('warehouse.manage') or public.has_permission('orders.view') or public.has_permission('*'));
create policy voucher_items_staff on public.voucher_items for all using(public.has_permission('vouchers.manage') or public.has_permission('*')) with check(public.has_permission('vouchers.manage') or public.has_permission('*'));
create policy voucher_usages_staff on public.voucher_usages for select using(public.has_permission('vouchers.manage') or public.has_permission('orders.view') or public.has_permission('*'));

drop policy if exists "catalog images admin insert" on storage.objects;drop policy if exists "catalog images admin update" on storage.objects;drop policy if exists "catalog images admin delete" on storage.objects;
drop policy if exists "catalog images catalog insert" on storage.objects;drop policy if exists "catalog images catalog update" on storage.objects;drop policy if exists "catalog images catalog delete" on storage.objects;
create policy "catalog images catalog insert" on storage.objects for insert with check(bucket_id='catalog' and (public.has_permission('catalog.manage') or public.has_permission('*')));
create policy "catalog images catalog update" on storage.objects for update using(bucket_id='catalog' and (public.has_permission('catalog.manage') or public.has_permission('*'))) with check(bucket_id='catalog' and (public.has_permission('catalog.manage') or public.has_permission('*')));
create policy "catalog images catalog delete" on storage.objects for delete using(bucket_id='catalog' and (public.has_permission('catalog.manage') or public.has_permission('*')));

revoke update on public.profiles from authenticated;grant update(full_name,phone,address,city,postal_code,avatar_url) on public.profiles to authenticated;
grant update on public.site_settings to authenticated;
grant select on public.admin_activity_logs to authenticated;
notify pgrst,'reload schema';

-- ============================================================================
-- END SOURCE: access-security.sql
-- ============================================================================

-- Paksa PostgREST membaca skema terbaru setelah seluruh restore selesai.
notify pgrst, 'reload schema';

-- Ringkasan tabel publik hasil restore.
select table_name
from information_schema.tables
where table_schema = 'public'
order by table_name;
