-- AOC FIX HARGA JUAL + STOK
-- Harga jual yang kosong/0 untuk item yang sudah diaktifkan sebagai produk jual
-- otomatis memakai harga dasar sebagai nilai awal. Tidak mengubah harga sewa.

update public.items
set sale_price = price
where sale_enabled = true
  and coalesce(sale_price, 0) <= 0
  and coalesce(price, 0) > 0;

-- Sinkronisasi stok item non-varian dari stok lokasi.
-- Item yang memiliki varian tetap memakai stok varian per lokasi.
update public.items i
set stock = coalesce((
  select sum(greatest(0, coalesce(s.stock,0)))
  from public.item_location_stock s
  where s.item_id = i.id
    and s.variant_id is null
), 0)
where not exists (
  select 1 from public.item_variants v where v.item_id = i.id and coalesce(v.is_active,true) = true
);

-- Audit stok varian: query ini sengaja hanya membaca data agar admin dapat
-- menemukan stok placeholder/abnormal seperti 9999 tanpa menghapus stok nyata.
select i.id, i.title, v.id as variant_id, v.name as variant_name, v.stock
from public.items i
join public.item_variants v on v.item_id = i.id
where i.type = 'product'
  and coalesce(v.stock,0) >= 9999
order by v.stock desc, i.title;
