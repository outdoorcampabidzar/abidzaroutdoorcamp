-- AOC: FIX STOCK EDITOR -> STOCK LOKASI
-- Menyamakan stok yang diedit di Admin > Sewa Item dengan stok lokasi.
-- Default lokasi: lokasi aktif dengan sort_order paling kecil.
-- Jika item memakai varian, stok varian disinkronkan; stok item utama tidak
-- membuat baris ganda.

create or replace function public.aoc_sync_editor_stock_to_location()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_location uuid;
begin
  if pg_trigger_depth() > 1 then return new; end if;
  select id into v_location from public.aoc_locations
  where is_active=true order by sort_order limit 1;
  if v_location is null then return new; end if;

  if TG_TABLE_NAME='items' then
    if new.type='product' and coalesce(new.rental_enabled,false)
       and not exists(select 1 from public.item_variants where item_id=new.id)
       and (tg_op='INSERT' or new.stock is distinct from old.stock) then
      insert into public.item_location_stock(item_id,variant_id,location_id,stock,updated_at)
      values(new.id,null,v_location,greatest(coalesce(new.stock,0),0),now())
      on conflict(item_id,variant_id,location_id)
      do update set stock=excluded.stock,updated_at=now();
    end if;
  elsif TG_TABLE_NAME='item_variants' then
    if tg_op='INSERT' or new.stock is distinct from old.stock then
      insert into public.item_location_stock(item_id,variant_id,location_id,stock,updated_at)
      values(new.item_id,new.id,v_location,greatest(coalesce(new.stock,0),0),now())
      on conflict(item_id,variant_id,location_id)
      do update set stock=excluded.stock,updated_at=now();
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists aoc_sync_editor_item_stock on public.items;
create trigger aoc_sync_editor_item_stock
after insert or update of stock on public.items
for each row execute function public.aoc_sync_editor_stock_to_location();

drop trigger if exists aoc_sync_editor_variant_stock on public.item_variants;
create trigger aoc_sync_editor_variant_stock
after insert or update of stock on public.item_variants
for each row execute function public.aoc_sync_editor_stock_to_location();

-- Repair data lama: pindahkan stok yang selama ini hanya tersimpan di editor
-- ke lokasi aktif pertama jika belum ada baris lokasi.
do $$
declare v_location uuid;
begin
  select id into v_location from public.aoc_locations where is_active=true order by sort_order limit 1;
  if v_location is not null then
    insert into public.item_location_stock(item_id,variant_id,location_id,stock,updated_at)
    select i.id,null,v_location,greatest(i.stock,0),now()
    from public.items i
    where i.type='product' and coalesce(i.rental_enabled,false)
      and not exists(select 1 from public.item_variants v where v.item_id=i.id)
      and not exists(select 1 from public.item_location_stock s where s.item_id=i.id and s.variant_id is null and s.location_id=v_location);

    insert into public.item_location_stock(item_id,variant_id,location_id,stock,updated_at)
    select v.item_id,v.id,v_location,greatest(v.stock,0),now()
    from public.item_variants v join public.items i on i.id=v.item_id
    where i.type='product' and coalesce(i.rental_enabled,false)
      and not exists(select 1 from public.item_location_stock s where s.item_id=v.item_id and s.variant_id=v.id and s.location_id=v_location);
  end if;
end $$;

notify pgrst,'reload schema';
