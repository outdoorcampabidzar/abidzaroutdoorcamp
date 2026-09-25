-- AOC Member QR compatibility patch
-- QR payload remains the legacy membership card_number.
-- The scanner resolves it server-side and returns member + order history.

-- Ensure the secure lookup function from AOC-ULTIMATE-SYSTEM-ENHANCEMENT.sql is installed.
-- This is intentionally not a client-side direct orders lookup.

revoke all on function public.aoc_secure_member_lookup(text) from public;
grant execute on function public.aoc_secure_member_lookup(text) to authenticated;
