-- AbidzarOutdoorcamp - SECURITY HARDENING untuk Coin Shop / Gacha
-- Jalankan SETELAH semua SQL utama, terutama access-security.sql.
-- Script ini aman dijalankan berulang kali.

-- 1) Fungsi internal pemberian coin TIDAK boleh dipanggil langsung dari browser.
revoke all on function public.award_order_coins(uuid) from public;
revoke execute on function public.award_order_coins(uuid) from authenticated;
grant execute on function public.award_order_coins(uuid) to service_role;

-- 2) Fungsi trigger internal juga tidak perlu dipanggil customer.
revoke all on function public.coin_award_order_trigger() from public;
revoke execute on function public.coin_award_order_trigger() from authenticated;

-- 3) Pastikan akses pengelolaan Coin Shop hanya untuk permission khusus.
-- Super Admin tetap lolos karena permission '*'.
drop policy if exists "coins own read" on public.customer_coins;
create policy "coins own read" on public.customer_coins
for select to authenticated
using (
  user_id = auth.uid()
  or public.has_permission('coinshop.manage')
  or public.has_permission('*')
);

drop policy if exists "coin tx own read" on public.coin_transactions;
create policy "coin tx own read" on public.coin_transactions
for select to authenticated
using (
  user_id = auth.uid()
  or public.has_permission('coinshop.manage')
  or public.has_permission('*')
);

drop policy if exists "shop rewards public read" on public.shop_rewards;
create policy "shop rewards public read" on public.shop_rewards
for select to authenticated
using (
  is_active = true
  or public.has_permission('coinshop.manage')
  or public.has_permission('*')
);

drop policy if exists "shop rewards admin all" on public.shop_rewards;
create policy "shop rewards admin all" on public.shop_rewards
for all to authenticated
using (
  public.has_permission('coinshop.manage')
  or public.has_permission('*')
)
with check (
  public.has_permission('coinshop.manage')
  or public.has_permission('*')
);

drop policy if exists "shop redemptions own read" on public.shop_redemptions;
create policy "shop redemptions own read" on public.shop_redemptions
for select to authenticated
using (
  user_id = auth.uid()
  or public.has_permission('coinshop.manage')
  or public.has_permission('*')
);

drop policy if exists "coin settings admin" on public.coin_settings;
create policy "coin settings admin" on public.coin_settings
for all to authenticated
using (
  public.has_permission('coinshop.manage')
  or public.has_permission('*')
)
with check (
  public.has_permission('coinshop.manage')
  or public.has_permission('*')
);

-- 4) Tidak memberikan INSERT/UPDATE/DELETE langsung ke customer.
revoke insert, update, delete on public.customer_coins from authenticated;
revoke insert, update, delete on public.coin_transactions from authenticated;
revoke insert, update, delete on public.shop_redemptions from authenticated;

-- 5) Fungsi gacha/redemption tetap boleh dipanggil customer karena fungsi tersebut
-- melakukan validasi auth.uid(), saldo, stok, voucher, dan transaksi secara atomik.
revoke all on function public.redeem_shop_reward(uuid) from public;
grant execute on function public.redeem_shop_reward(uuid) to authenticated;

revoke all on function public.get_shop_gacha_options(uuid) from public;
grant execute on function public.get_shop_gacha_options(uuid) to authenticated;

revoke all on function public.preview_voucher(text,numeric,jsonb) from public;
grant execute on function public.preview_voucher(text,numeric,jsonb) to authenticated;

-- 6) Pastikan permission khusus tersedia. Super Admin sudah punya '*'.
insert into public.role_permissions(role, permission)
values ('super_admin','coinshop.manage')
on conflict do nothing;

-- 7) Cek cepat: fungsi internal seharusnya hanya service_role.
-- SELECT routine_name, grantee, privilege_type
-- FROM information_schema.routine_privileges
-- WHERE routine_schema='public' AND routine_name='award_order_coins';
