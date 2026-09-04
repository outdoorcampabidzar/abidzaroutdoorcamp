-- PATCH GACHA QUOTA - COMPATIBILITY FIX
-- Versi FINAL2 diperbaiki: coin-shop.sql sekarang menjadi sumber fungsi Gacha utama.
-- Jangan menimpa redeem_shop_reward dengan versi lama karena versi lama dapat
-- memperlakukan stock=0 sebagai habis dan belum memakai bobot probabilitas.
-- Jalankan coin-shop.sql terbaru setelah voucher-management.sql.

alter table public.vouchers
  add column if not exists gacha_rarity text not null default 'common',
  add column if not exists gacha_probability numeric(7,4) not null default 60;

alter table public.vouchers drop constraint if exists vouchers_gacha_rarity_check;
alter table public.vouchers add constraint vouchers_gacha_rarity_check
  check (gacha_rarity in ('common','uncommon','rare','epic','legendary'));

alter table public.vouchers drop constraint if exists vouchers_gacha_probability_check;
alter table public.vouchers add constraint vouchers_gacha_probability_check
  check (gacha_probability >= 0 and gacha_probability <= 100);

-- 0 pada shop_rewards.stock = unlimited, bukan habis.
-- Kuota template voucher tetap dibatasi oleh vouchers.quota.
