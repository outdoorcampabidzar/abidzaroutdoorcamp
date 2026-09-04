-- PATCH: AUTO DELETE VOUCHER YANG SUDAH HABIS (TERPAKAI >= KUOTA)
-- Jalankan SEKALI di Supabase SQL Editor setelah backup database.
--
-- Perbaikan ini mencakup:
-- 1) Voucher template Gacha: kuota terakhir dimenangkan -> sumber dihapus.
-- 2) Voucher AOC yang sudah diberikan ke pelanggan: saat dipakai dan mencapai
--    quota -> voucher langsung dihapus.
--
-- Riwayat tidak ikut hilang. voucher_usages menyimpan voucher_code dan
-- voucher_id dibuat nullable + ON DELETE SET NULL.

-- 1. Lepaskan FK lama yang melarang penghapusan voucher yang punya riwayat.
alter table public.voucher_usages
  alter column voucher_id drop not null;

alter table public.voucher_usages
  drop constraint if exists voucher_usages_voucher_id_fkey;

alter table public.voucher_usages
  add constraint voucher_usages_voucher_id_fkey
  foreign key (voucher_id) references public.vouchers(id) on delete set null;

-- 2. Riwayat penggunaan tetap dicatat walaupun voucher sudah dihapus.
create or replace function public.track_voucher_usage()
returns trigger language plpgsql security definer set search_path = public
as $$
declare v_id uuid;
begin
  if new.voucher_code is null then return new; end if;
  select id into v_id from public.vouchers where code = new.voucher_code;

  if new.status in ('confirmed', 'paid', 'completed')
     and old.status not in ('confirmed', 'paid', 'completed') then
    insert into public.voucher_usages(
      voucher_id, order_id, user_id, voucher_code, discount, status
    ) values (v_id, new.id, new.user_id, new.voucher_code, new.discount, 'used')
    on conflict (order_id) do update set
      voucher_id = excluded.voucher_id,
      status = 'used', used_at = now(), reversed_at = null;
  elsif old.status in ('confirmed', 'paid', 'completed')
        and new.status in ('cancelled', 'failed', 'refunded') then
    update public.voucher_usages set status = 'reversed', reversed_at = now()
    where order_id = new.id;
  end if;
  return new;
end;
$$;

-- 3. Bersihkan voucher lama yang memang sudah habis.
-- History tetap aman karena FK di atas memakai ON DELETE SET NULL.
delete from public.vouchers
where quota > 0 and coalesce(used_count,0) >= quota;

-- 4. coin-shop.sql versi paket sudah menghapus voucher sumber Gacha setelah
--    pemakaian terakhir. Untuk voucher yang dipakai saat checkout,
--    btzpay-payment.sql dan rental-calendar.sql versi paket juga menghapusnya.
