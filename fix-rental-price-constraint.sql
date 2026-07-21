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
