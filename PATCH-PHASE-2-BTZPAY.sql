-- Phase 2: payment gateway hardening.
-- Aman dijalankan setelah btzpay-payment.sql.
-- Tidak menghapus data transaksi.

alter table public.payment_transactions
  add column if not exists gateway_mode text not null default 'rental';

create index if not exists payment_gateway_mode_idx
  on public.payment_transactions(gateway_mode);

-- Catatan: API key TIDAK disimpan di database. Set melalui Supabase Edge Function Secrets:
-- BTZPAY_API_KEY
-- BTZPAY_API_KEY_SALE   (opsional, fallback ke BTZPAY_API_KEY)
-- BTZPAY_API_KEY_RENTAL (opsional, fallback ke BTZPAY_API_KEY)
-- PUBLIC_SITE_URL
-- BTZPAY_CRON_SECRET
