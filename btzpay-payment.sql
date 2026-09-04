-- AbidzarOutdoorcamp - Integrasi Pembayaran BTZPay
-- Jalankan setelah sql/BACKUP-SELURUH-DATABASE.sql, site-settings.sql, dan rental-calendar.sql.

alter table public.orders add column if not exists payment_status text not null default 'unpaid';
alter table public.orders add column if not exists paid_at timestamptz;

create table if not exists public.payment_transactions (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  gateway text not null default 'btzpay',
  gateway_transaction_id text not null unique,
  payment_method text not null,
  amount numeric(14,2) not null check (amount >= 0),
  total_amount numeric(14,2) not null check (total_amount >= 0),
  status text not null default 'pending'
    check (status in ('pending','paid','expired','cancelled','refunded','failed')),
  payment_url text,
  expires_at timestamptz,
  paid_at timestamptz,
  cancelled_at timestamptz,
  failure_reason text,
  last_checked_at timestamptz,
  raw_response jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Access key gateway dipisahkan agar tidak pernah dapat dibaca browser.
create table if not exists public.payment_gateway_secrets (
  payment_id uuid primary key references public.payment_transactions(id) on delete cascade,
  access_key text not null
);

create table if not exists public.payment_webhook_logs (
  id bigint generated always as identity primary key,
  gateway_transaction_id text,
  event_status text,
  payload jsonb not null default '{}'::jsonb,
  verified boolean not null default false,
  error_message text,
  created_at timestamptz not null default now()
);

create index if not exists payment_order_idx on public.payment_transactions(order_id, created_at desc);
create index if not exists payment_pending_expiry_idx on public.payment_transactions(expires_at)
  where status = 'pending';

alter table public.payment_transactions enable row level security;
alter table public.payment_gateway_secrets enable row level security;
alter table public.payment_webhook_logs enable row level security;

drop policy if exists "payment owner or admin read" on public.payment_transactions;
create policy "payment owner or admin read" on public.payment_transactions
for select to authenticated using (
  exists (select 1 from public.orders o where o.id = order_id and (o.user_id = auth.uid() or public.is_admin()))
);

drop policy if exists "payment logs admin read" on public.payment_webhook_logs;
create policy "payment logs admin read" on public.payment_webhook_logs
for select to authenticated using (public.is_admin());

revoke all on public.payment_transactions from anon, authenticated;
grant select on public.payment_transactions to authenticated;
revoke all on public.payment_gateway_secrets from anon, authenticated;
revoke all on public.payment_webhook_logs from anon, authenticated;
grant select on public.payment_webhook_logs to authenticated;
grant all on public.payment_transactions, public.payment_gateway_secrets, public.payment_webhook_logs to service_role;
grant usage, select on sequence public.payment_webhook_logs_id_seq to service_role;

create or replace function public.apply_btzpay_status(
  p_transaction_id text,
  p_status text,
  p_raw jsonb default '{}'::jsonb,
  p_reason text default null
)
returns void language plpgsql security definer set search_path = public
as $$
declare
  v_payment public.payment_transactions%rowtype;
  v_order public.orders%rowtype;
  v_line public.order_items%rowtype;
  v_status text;
  v_was_paid boolean;
  v_now_paid boolean;
begin
  if auth.role() <> 'service_role' then raise exception 'Service role diperlukan'; end if;

  v_status := case lower(coalesce(p_status, ''))
    when 'sukses' then 'paid' when 'paid' then 'paid'
    when 'expired' then 'expired'
    when 'cancel' then 'cancelled' when 'cancelled' then 'cancelled'
    when 'refunded' then 'refunded'
    when 'gagal' then 'failed' when 'failed' then 'failed'
    else 'pending' end;

  select * into v_payment from public.payment_transactions
  where gateway_transaction_id = p_transaction_id for update;
  if not found then raise exception 'Transaksi pembayaran tidak ditemukan'; end if;

  if v_payment.status in ('expired','cancelled','refunded','failed') and v_status = 'pending' then
    return;
  end if;
  if v_payment.status in ('expired','cancelled','refunded','failed') and v_status = 'paid' then
    raise exception 'Pembayaran diterima setelah transaksi ditutup; lakukan pemeriksaan dan refund manual';
  end if;

  select * into v_order from public.orders where id = v_payment.order_id for update;
  v_was_paid := v_payment.status = 'paid' or v_order.status in ('confirmed','paid','completed');
  v_now_paid := v_status = 'paid';

  if not v_was_paid and v_now_paid then
    for v_line in select * from public.order_items where order_id = v_order.id loop
      if v_line.item_type = 'trip' then
        update public.items set quota = quota - v_line.quantity
        where id = v_line.item_id and coalesce(quota, 0) >= v_line.quantity;
        if not found then raise exception 'Kuota % tidak cukup', v_line.title_snapshot; end if;
      end if;
    end loop;
    if v_order.voucher_code is not null then
      update public.vouchers set used_count = used_count + 1
      where code = v_order.voucher_code and used_count < quota;
      if not found then raise exception 'Kuota voucher habis'; end if;
      -- Voucher yang sudah mencapai kuota langsung dihapus. Riwayat tetap
      -- tersimpan di voucher_usages/shop_redemptions melalui voucher_code.
      delete from public.vouchers
      where code = v_order.voucher_code
        and coalesce(used_count,0) >= quota;
    end if;
  elsif v_was_paid and v_status in ('refunded','cancelled','expired','failed') then
    for v_line in select * from public.order_items where order_id = v_order.id loop
      if v_line.item_type = 'trip' then
        update public.items set quota = coalesce(quota, 0) + v_line.quantity where id = v_line.item_id;
      end if;
    end loop;
    if v_order.voucher_code is not null then
      update public.vouchers set used_count = greatest(used_count - 1, 0) where code = v_order.voucher_code;
    end if;
  end if;

  update public.payment_transactions set
    status = v_status,
    paid_at = case when v_status = 'paid' then coalesce(paid_at, now()) else paid_at end,
    cancelled_at = case when v_status in ('expired','cancelled','refunded','failed') then coalesce(cancelled_at, now()) else cancelled_at end,
    failure_reason = coalesce(nullif(p_reason, ''), failure_reason),
    last_checked_at = now(), raw_response = coalesce(p_raw, '{}'::jsonb), updated_at = now()
  where id = v_payment.id;

  update public.orders set
    payment_status = v_status,
    paid_at = case when v_status = 'paid' then coalesce(paid_at, now()) else paid_at end,
    status = case
      when v_status = 'paid' then 'paid'
      when v_status in ('expired','cancelled','failed') and status in ('pending','confirmed','paid') then 'cancelled'
      when v_status = 'refunded' then 'cancelled'
      else status end,
    updated_at = now()
  where id = v_order.id;
end;
$$;

revoke all on function public.apply_btzpay_status(text,text,jsonb,text) from public;
grant execute on function public.apply_btzpay_status(text,text,jsonb,text) to service_role;
