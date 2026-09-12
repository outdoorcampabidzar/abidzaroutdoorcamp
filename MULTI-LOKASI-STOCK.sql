-- AOC MULTI-LOKASI STOCK
-- Memisahkan stok Toko 1 dan Toko 2. Jalankan SEKALI di Supabase SQL Editor.
begin;

create table if not exists public.aoc_locations (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  address text,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

insert into public.aoc_locations(code,name,sort_order)
values ('TOKO1','Toko 1',1), ('TOKO2','Toko 2',2)
on conflict (code) do update set name=excluded.name;

alter table public.profiles add column if not exists location_id uuid references public.aoc_locations(id) on delete set null;
alter table public.orders add column if not exists location_id uuid references public.aoc_locations(id) on delete set null;

create table if not exists public.item_location_stock (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id) on delete cascade,
  variant_id uuid references public.item_variants(id) on delete cascade,
  location_id uuid not null references public.aoc_locations(id) on delete cascade,
  stock integer not null default 0 check (stock >= 0),
  updated_at timestamptz not null default now(),
  unique(item_id, variant_id, location_id)
);

create index if not exists item_location_stock_lookup_idx
on public.item_location_stock(item_id, variant_id, location_id);

alter table public.item_location_stock enable row level security;
drop policy if exists "aoc location stock public read" on public.item_location_stock;
create policy "aoc location stock public read" on public.item_location_stock
for select using (true);
drop policy if exists "aoc location stock admin write" on public.item_location_stock;
create policy "aoc location stock admin write" on public.item_location_stock
for all to authenticated using (public.is_admin()) with check (public.is_admin());

alter table public.aoc_locations enable row level security;
drop policy if exists "aoc locations public read" on public.aoc_locations;
create policy "aoc locations public read" on public.aoc_locations
for select using (is_active or public.is_admin());
drop policy if exists "aoc locations admin write" on public.aoc_locations;
create policy "aoc locations admin write" on public.aoc_locations
for all to authenticated using (public.is_admin()) with check (public.is_admin());

grant select on public.aoc_locations, public.item_location_stock to anon, authenticated;

-- Lokasi default untuk akun lama.
update public.profiles
set location_id=(select id from public.aoc_locations where code='TOKO1')
where location_id is null;

-- Migrasi stok lama: stok yang sebelumnya tercampur dianggap milik Toko 1.
insert into public.item_location_stock(item_id,variant_id,location_id,stock)
select i.id,null,l.id,greatest(coalesce(i.stock,0),0)
from public.items i
cross join lateral (select id from public.aoc_locations where code='TOKO1') l
where i.type='product'
  and coalesce(i.stock,0)>0
  and not exists (
    select 1 from public.item_location_stock s
    where s.item_id=i.id and s.variant_id is null and s.location_id=l.id
  );

insert into public.item_location_stock(item_id,variant_id,location_id,stock)
select v.item_id,v.id,l.id,greatest(coalesce(v.stock,0),0)
from public.item_variants v
cross join lateral (select id from public.aoc_locations where code='TOKO1') l
where coalesce(v.stock,0)>0
  and not exists (
    select 1 from public.item_location_stock s
    where s.item_id=v.item_id and s.variant_id=v.id and s.location_id=l.id
  );

create or replace function public.aoc_current_location_id()
returns uuid
language plpgsql stable security definer set search_path=public
as $$
declare v uuid;
begin
  if auth.uid() is not null then
    select location_id into v from public.profiles where id=auth.uid();
  end if;
  return coalesce(v,(select id from public.aoc_locations where code='TOKO1' limit 1));
end;
$$;

create or replace function public.aoc_location_stock(p_item_id uuid,p_variant_id uuid default null)
returns integer
language sql stable security definer set search_path=public
as $$
  select coalesce(sum(s.stock),0)::integer
  from public.item_location_stock s
  where s.item_id=p_item_id
    and ((p_variant_id is null and s.variant_id is null) or s.variant_id=p_variant_id)
    and s.location_id=public.aoc_current_location_id();
$$;

create or replace function public.aoc_set_current_location(p_location_id uuid)
returns void
language plpgsql security definer set search_path=public
as $$
begin
  if auth.uid() is null then raise exception 'Login diperlukan'; end if;
  if not exists(select 1 from public.aoc_locations where id=p_location_id and is_active) then
    raise exception 'Lokasi tidak valid';
  end if;
  update public.profiles set location_id=p_location_id where id=auth.uid();
end;
$$;

create or replace function public.aoc_set_location_stock(
  p_item_id uuid,p_location_id uuid,p_stock integer,p_variant_id uuid default null
)
returns void
language plpgsql security definer set search_path=public
as $$
declare v_total integer;
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  if p_stock < 0 then raise exception 'Stok tidak boleh negatif'; end if;
  if not exists(select 1 from public.aoc_locations where id=p_location_id and is_active) then
    raise exception 'Lokasi tidak valid';
  end if;
  if p_variant_id is not null and not exists(
    select 1 from public.item_variants where id=p_variant_id and item_id=p_item_id
  ) then raise exception 'Varian tidak valid'; end if;

  insert into public.item_location_stock(item_id,variant_id,location_id,stock,updated_at)
  values(p_item_id,p_variant_id,p_location_id,p_stock,now())
  on conflict(item_id,variant_id,location_id)
  do update set stock=excluded.stock,updated_at=now();

  if p_variant_id is null then
    select coalesce(sum(stock),0) into v_total
    from public.item_location_stock
    where item_id=p_item_id and variant_id is null;
    update public.items set stock=v_total where id=p_item_id;
  else
    select coalesce(sum(stock),0) into v_total
    from public.item_location_stock
    where item_id=p_item_id and variant_id=p_variant_id;
    update public.item_variants set stock=v_total where id=p_variant_id;
  end if;
end;
$$;

grant execute on function public.aoc_current_location_id() to anon,authenticated;
grant execute on function public.aoc_location_stock(uuid,uuid) to anon,authenticated;
grant execute on function public.aoc_set_current_location(uuid) to authenticated;
grant execute on function public.aoc_set_location_stock(uuid,uuid,integer,uuid) to authenticated;

-- Order selalu membawa lokasi akun saat checkout.
create or replace function public.aoc_orders_set_location()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.location_id is null and auth.uid() is not null then
    new.location_id := public.aoc_current_location_id();
  end if;
  return new;
end;
$$;
drop trigger if exists aoc_orders_set_location_trigger on public.orders;
create trigger aoc_orders_set_location_trigger
before insert on public.orders
for each row execute function public.aoc_orders_set_location();

-- Batasi reservation rental ke lokasi yang sama.
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
      and o.location_id = public.aoc_current_location_id()
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
      and o.location_id = public.aoc_current_location_id()
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
      and o.location_id = public.aoc_current_location_id()
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

  select public.aoc_location_stock(id, null) into v_stock
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

  select public.aoc_location_stock(i.id, v.id) into v_stock
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
  select public.aoc_location_stock(id, null) into v_stock
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
  select public.aoc_location_stock(i.id, v.id) into v_stock
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
-- Stok SALE dipotong/dikembalikan pada lokasi pesanan.
create or replace function public.aoc_sync_location_sale_stock()
returns trigger language plpgsql security definer set search_path=public as $$
declare
  l public.order_items%rowtype;
  loc uuid;
  cur integer;
begin
  select location_id into loc from public.orders where id=new.id;
  if loc is null then loc := public.aoc_current_location_id(); end if;

  if new.status='paid' and old.status<>'paid' then
    for l in select * from public.order_items where order_id=new.id and item_type='product' and fulfillment_type='sale' loop
      if l.variant_id is null then
        select stock into cur from public.item_location_stock where item_id=l.item_id and variant_id is null and location_id=loc for update;
      else
        select stock into cur from public.item_location_stock where item_id=l.item_id and variant_id=l.variant_id and location_id=loc for update;
      end if;
      if coalesce(cur,0) < l.quantity then
        raise exception 'Stok % di lokasi pesanan tidak cukup',l.title_snapshot;
      end if;
      update public.item_location_stock
      set stock=stock-l.quantity,updated_at=now()
      where item_id=l.item_id and location_id=loc
        and ((l.variant_id is null and variant_id is null) or variant_id=l.variant_id);
    end loop;
  elsif new.status in ('cancelled','completed','returned') and old.status='paid' then
    for l in select * from public.order_items where order_id=new.id and item_type='product' and fulfillment_type='sale' loop
      insert into public.item_location_stock(item_id,variant_id,location_id,stock)
      values(l.item_id,l.variant_id,loc,l.quantity)
      on conflict(item_id,variant_id,location_id)
      do update set stock=item_location_stock.stock+l.quantity,updated_at=now();
    end loop;
  end if;
  return new;
end;
$$;

drop trigger if exists zzz_aoc_location_sale_stock_trigger on public.orders;
create trigger zzz_aoc_location_sale_stock_trigger
after update of status on public.orders
for each row when(old.status is distinct from new.status)
execute function public.aoc_sync_location_sale_stock();

-- Sinkronkan total legacy setelah perubahan stok lokasi.
create or replace function public.aoc_refresh_legacy_stock(p_item_id uuid,p_variant_id uuid default null)
returns void language plpgsql security definer set search_path=public as $$
declare v_total integer;
begin
  if p_variant_id is null then
    select coalesce(sum(stock),0) into v_total from public.item_location_stock where item_id=p_item_id and variant_id is null;
    update public.items set stock=v_total where id=p_item_id;
  else
    select coalesce(sum(stock),0) into v_total from public.item_location_stock where item_id=p_item_id and variant_id=p_variant_id;
    update public.item_variants set stock=v_total where id=p_variant_id;
  end if;
end;
$$;

-- Trigger agar total lama tetap sama dengan jumlah semua toko.
create or replace function public.aoc_refresh_total_after_location_stock()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  perform public.aoc_refresh_legacy_stock(coalesce(new.item_id,old.item_id),coalesce(new.variant_id,old.variant_id));
  if TG_OP='DELETE' then return old; else return new; end if;
end;
$$;
drop trigger if exists aoc_refresh_total_location_stock on public.item_location_stock;
create trigger aoc_refresh_total_location_stock
after insert or update or delete on public.item_location_stock
for each row execute function public.aoc_refresh_total_after_location_stock();

notify pgrst,'reload schema';
commit;
