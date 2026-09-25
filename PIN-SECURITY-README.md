# AOC PIN Security Hardening

This patch adds a server-side security gate for high-impact mutations.

## Protected operations
Authenticated browser writes to orders, order items/returns/refunds, payments, vouchers, catalog/inventory, locations, shop/coin settings, announcements and trip management require a fresh transaction-PIN verification session.

## Important
- The PIN is hashed with bcrypt and is never returned to the browser.
- 5 failed PIN attempts lock verification for 15 minutes.
- A successful verification session lasts 2 minutes and is consumed by an order insert.
- Existing PINs cannot be replaced without proving the current PIN.
- Service-role/background jobs with no `auth.uid()` are not blocked by this browser-user gate.
- RLS must remain enabled; this patch is an additional server-side gate, not a replacement for RLS.

## Installation
Run `PATCH-TRANSACTION-PIN-SECURITY.sql` first if the PIN tables/functions do not exist, then run `PATCH-PIN-SECURITY-ALL-SENSITIVE.sql` in Supabase SQL Editor.

If the current website still calls `set_transaction_pin(p_pin => ...)` for first-time registration, that first setup remains supported. Changing an existing PIN requires the current PIN.
