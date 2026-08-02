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