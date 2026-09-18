-- ============================================================================
-- AOC - FIX TAMBAH ITEM TRANSAKSIONAL
--
-- Memperbaiki proses Tambah Item Sewa agar item, kategori, gambar, varian,
-- inventaris, dan harga paket disimpan dalam SATU transaksi PostgreSQL.
-- Jika salah satu bagian gagal, seluruh proses di-ROLLBACK.
--
-- Jalankan setelah SQL fondasi AOC, terutama:
--   catalog-management.sql
--   access-security.sql
--   MULTI-LOKASI-STOCK.sql / PATCH-FIX-CHECKOUT-TOKO.sql
--   AOC-FINAL-FIX.sql
--   AOC-ULTIMATE-FINAL.sql
-- ============================================================================

create or replace function public.secure_admin_create_rental_item(
  p_payload jsonb,
  p_category_name text default null,
  p_gallery_urls text[] default '{}',
  p_variants jsonb default '[]'::jsonb,
  p_inventory_units jsonb default '[]'::jsonb,
  p_price_tiers jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item_id uuid;
  v_category_id uuid;
  v_variant_id uuid;
  v_variant record;
  v_tier jsonb;
  v_gallery text;
  v_variant_name text;
  v_slug text;
  v_title text;
  v_category_name text;
  v_location_id uuid;
begin
  if not public.has_permission('catalog.manage') and not public.has_permission('*') then
    raise exception 'Izin catalog.manage diperlukan untuk menambahkan item.';
  end if;

  v_title := nullif(trim(coalesce(p_payload->>'title','')), '');
  v_slug := nullif(trim(coalesce(p_payload->>'slug','')), '');
  if v_title is null then raise exception 'Nama item wajib diisi.'; end if;
  if v_slug is null then raise exception 'Slug item wajib diisi.'; end if;

  -- Kategori: cari berdasarkan slug/nama; jika belum ada, buat.
  v_category_name := nullif(trim(coalesce(p_category_name,'')), '');
  if v_category_name is not null then
    select id into v_category_id
    from public.item_categories
    where lower(name) = lower(v_category_name)
       or slug = regexp_replace(lower(v_category_name), '[^a-z0-9]+', '-', 'g')
    order by id
    limit 1;

    if v_category_id is null then
      insert into public.item_categories(name, slug)
      values (
        v_category_name,
        trim(both '-' from regexp_replace(lower(v_category_name), '[^a-z0-9]+', '-', 'g'))
      )
      on conflict (slug) do update set name = excluded.name, updated_at = now()
      returning id into v_category_id;
    end if;
  end if;

  insert into public.items(
    title, slug, type, description, image_url, price, sale_price, stock,
    sale_enabled, rental_enabled, category_id, deposit, is_featured,
    sort_order, location, trip_date, quota, requires_guarantee,
    guarantee_note, is_active
  )
  values (
    v_title,
    v_slug,
    'product',
    nullif(trim(coalesce(p_payload->>'description','')), ''),
    nullif(trim(coalesce(p_payload->>'image_url','')), ''),
    greatest(coalesce((p_payload->>'price')::numeric,0),0),
    greatest(coalesce((p_payload->>'sale_price')::numeric,0),0),
    greatest(coalesce((p_payload->>'stock')::integer,0),0),
    coalesce((p_payload->>'sale_enabled')::boolean,false),
    coalesce((p_payload->>'rental_enabled')::boolean,true),
    v_category_id,
    greatest(coalesce((p_payload->>'deposit')::numeric,0),0),
    coalesce((p_payload->>'is_featured')::boolean,false),
    coalesce((p_payload->>'sort_order')::integer,0),
    null, null, null,
    coalesce((p_payload->>'requires_guarantee')::boolean,false),
    nullif(trim(coalesce(p_payload->>'guarantee_note','')), ''),
    coalesce((p_payload->>'is_active')::boolean,true)
  )
  returning id into v_item_id;

  -- Gambar utama + galeri.
  if nullif(trim(coalesce(p_payload->>'image_url','')), '') is not null then
    insert into public.item_images(item_id,image_url,alt_text,is_primary,sort_order)
    values(v_item_id, trim(p_payload->>'image_url'), v_title, true, 0);
  end if;

  if coalesce(array_length(p_gallery_urls,1),0) > 0 then
    foreach v_gallery in array p_gallery_urls loop
      if nullif(trim(v_gallery),'') is not null
         and trim(v_gallery) <> trim(coalesce(p_payload->>'image_url','')) then
        insert into public.item_images(item_id,image_url,alt_text,is_primary,sort_order)
        values(v_item_id,trim(v_gallery),v_title,false,
               (select coalesce(max(sort_order),0)+1 from public.item_images where item_id=v_item_id));
      end if;
    end loop;
  end if;

  -- Varian.
  for v_variant in
    select * from jsonb_to_recordset(coalesce(p_variants,'[]'::jsonb))
      as x(name text, capacity text, stock integer)
  loop
    if nullif(trim(coalesce(v_variant.name,'')),'') is null then
      raise exception 'Nama varian tidak boleh kosong.';
    end if;
    insert into public.item_variants(item_id,name,capacity,price_adjustment,stock,sort_order)
    values(v_item_id,trim(v_variant.name),nullif(trim(coalesce(v_variant.capacity,'')),''),0,
           greatest(coalesce(v_variant.stock,0),0),
           (select count(*) from public.item_variants where item_id=v_item_id))
    returning id into v_variant_id;
  end loop;

  -- Inventaris fisik.
  for v_variant in
    select * from jsonb_to_recordset(coalesce(p_inventory_units,'[]'::jsonb))
      as x(inventory_number text, condition text, status text, notes text)
  loop
    if nullif(trim(coalesce(v_variant.inventory_number,'')),'') is null then
      raise exception 'Nomor inventaris tidak boleh kosong.';
    end if;
    if coalesce(v_variant.condition,'good') not in ('new','good','fair','damaged') then
      raise exception 'Kondisi inventaris % tidak valid.', v_variant.inventory_number;
    end if;
    if coalesce(v_variant.status,'available') not in ('available','rented','damaged','maintenance','retired') then
      raise exception 'Status inventaris % tidak valid.', v_variant.inventory_number;
    end if;
    insert into public.inventory_units(item_id,inventory_number,condition,status,notes)
    values(v_item_id,trim(v_variant.inventory_number),coalesce(v_variant.condition,'good'),
           coalesce(v_variant.status,'available'),nullif(trim(coalesce(v_variant.notes,'')),''));
  end loop;

  -- Harga paket. variant_name harus cocok dengan varian yang baru dibuat,
  -- atau "semua varian" untuk harga default.
  for v_tier in select value from jsonb_array_elements(coalesce(p_price_tiers,'[]'::jsonb)) loop
    v_variant_name := lower(trim(coalesce(v_tier->>'variant_name','')));
    v_variant_id := null;
    if v_variant_name <> '' and v_variant_name <> 'semua varian' then
      select id into v_variant_id
      from public.item_variants
      where item_id=v_item_id and lower(name)=v_variant_name
      limit 1;
      if v_variant_id is null then
        raise exception 'Varian harga % tidak ditemukan.', v_tier->>'variant_name';
      end if;
    end if;
    insert into public.item_price_tiers(item_id,variant_id,label,duration_days,price,sort_order)
    values(
      v_item_id,
      v_variant_id,
      coalesce(nullif(trim(coalesce(v_tier->>'label','')), ''), concat(greatest(coalesce((v_tier->>'duration_days')::integer,1),1), ' hari')) ,
      greatest(coalesce((v_tier->>'duration_days')::integer,1),1),
      greatest(coalesce((v_tier->>'price')::numeric,0),0),
      (select count(*) from public.item_price_tiers where item_id=v_item_id)
    );
  end loop;

  -- Sinkronisasi stok toko untuk sistem multi-lokasi jika tabel tersedia.
  if to_regclass('public.item_location_stock') is not null then
    begin
      v_location_id := public.aoc_current_location_id();
    exception when undefined_function then
      v_location_id := null;
    end;
    if v_location_id is not null then
      insert into public.item_location_stock(item_id,variant_id,location_id,stock,updated_at)
      values(v_item_id,null,v_location_id,greatest(coalesce((p_payload->>'stock')::integer,0),0),now())
      on conflict(item_id,variant_id,location_id) do update set
        stock=excluded.stock, updated_at=now();

      for v_variant in
        select id, stock from public.item_variants where item_id=v_item_id
      loop
        insert into public.item_location_stock(item_id,variant_id,location_id,stock,updated_at)
        values(v_item_id,v_variant.id,v_location_id,greatest(coalesce(v_variant.stock,0),0),now())
        on conflict(item_id,variant_id,location_id) do update set
          stock=excluded.stock, updated_at=now();
      end loop;
    end if;
  end if;

  return jsonb_build_object('id',v_item_id,'item_id',v_item_id,'title',v_title,'success',true);
exception
  when unique_violation then
    raise exception 'Data duplikat. Periksa slug atau nomor inventaris.';
end;
$$;

grant execute on function public.secure_admin_create_rental_item(jsonb,text,text[],jsonb,jsonb,jsonb) to authenticated;

comment on function public.secure_admin_create_rental_item(jsonb,text,text[],jsonb,jsonb,jsonb)
is 'AOC: membuat item sewa beserta relasi katalog secara atomik dalam satu transaksi.';
