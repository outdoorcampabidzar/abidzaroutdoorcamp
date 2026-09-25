-- AOC FINAL FIX: PIN RPC AMBIGUITY
-- Run this if Supabase reports:
-- "Could not choose the best candidate function: public.set_transaction_pin(...)"
-- This removes the legacy overloaded function and leaves the mBanking API.

drop function if exists public.set_transaction_pin(text,text);

-- The canonical one-argument function is supplied by PATCH-PIN-USER-MBANKING.sql.
-- Run that patch as well if public.set_transaction_pin(text) does not exist.

notify pgrst, 'reload schema';
