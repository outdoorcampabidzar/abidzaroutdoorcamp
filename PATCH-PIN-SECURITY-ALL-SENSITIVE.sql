-- AOC SECURITY HARDENING: TRANSACTION PIN FOR SENSITIVE MUTATIONS
-- Run AFTER PATCH-TRANSACTION-PIN-SECURITY.sql and AFTER the base schema.
-- PIN is never stored in plaintext. Sensitive writes require a fresh server-side PIN session.

create extension if not exists pgcrypto with schema extensions;
create schema if not exists private;

-- Keep exactly ONE public setter signature. A previous migration created
-- set_transaction_pin(text,text DEFAULT NULL), which conflicts with the
-- mBanking set_transaction_pin(text) RPC in PostgREST. Remove that overload.
drop function if exists public.set_transaction_pin(text,text);

-- User creation is handled by the one-argument RPC. Existing PINs cannot be
-- silently replaced; PIN changes must use change_transaction_pin(old,new).
create or replace function public.set_transaction_pin(p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_pin text := trim(coalesce(p_pin, ''));
  v_exists boolean;
begin
  if v_user_id is null then raise exception 'Silakan login terlebih dahulu'; end if;
  if v_pin !~ '^\d{6}$' then raise exception 'PIN transaksi harus tepat 6 digit.'; end if;
  if v_pin ~ '^(.)\1{5}$' then raise exception 'PIN tidak boleh 6 angka yang sama.'; end if;

  select exists(select 1 from private.aoc_transaction_pins where user_id=v_user_id) into v_exists;
  if v_exists then
    raise exception 'PIN sudah dibuat. Untuk mengganti PIN, verifikasi PIN lama terlebih dahulu.';
  end if;

  insert into private.aoc_transaction_pins(user_id,pin_hash,failed_attempts,locked_until,updated_at)
  values(v_user_id,extensions.crypt(v_pin,extensions.gen_salt('bf',10)),0,null,now());

  delete from private.aoc_transaction_pin_sessions where user_id=v_user_id;
  return jsonb_build_object('success',true,'message','PIN transaksi berhasil dibuat.');
end;
$$;

-- Explicit server-side gate. Service-role/background operations (auth.uid() NULL)
-- are allowed to continue; browser-authenticated writes are not.
create or replace function public.aoc_require_fresh_transaction_pin()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_verified boolean := false;
begin
  if v_user_id is null then return coalesce(new, old); end if;
  select exists(
    select 1 from private.aoc_transaction_pin_sessions
    where user_id=v_user_id and verified_until > now()
  ) into v_verified;
  if not v_verified then
    raise exception 'PIN transaksi wajib diverifikasi untuk tindakan ini.' using errcode='42501';
  end if;
  return coalesce(new, old);
end;
$$;

-- Protect high-impact customer/admin mutations. Reads remain available according to RLS.
-- Missing tables are skipped so this patch remains compatible with installations where
-- an optional feature has not been installed.
do $$
declare t text; op text;
begin
  foreach t in array array[
    'orders','order_items','order_returns','order_refunds','payment_transactions',
    'vouchers','voucher_items','voucher_usages','items','item_variants','item_price_tiers',
    'inventory_units','aoc_locations','shop_rewards','coin_settings',
    'open_trips','trip_participants'
  ] loop
    if to_regclass('public.'||t) is not null then
      execute format('drop trigger if exists aoc_pin_gate_%I on public.%I',t,t);
      execute format('create trigger aoc_pin_gate_%I before insert or update or delete on public.%I for each row execute function public.aoc_require_fresh_transaction_pin()',t,t);
    end if;
  end loop;
end $$;

-- Do not expose private PIN tables directly.
revoke all on private.aoc_transaction_pins from public, anon, authenticated;
revoke all on private.aoc_transaction_pin_sessions from public, anon, authenticated;
revoke all on function public.aoc_require_fresh_transaction_pin() from public, anon, authenticated;
grant execute on function public.aoc_require_fresh_transaction_pin() to authenticated;

grant execute on function public.set_transaction_pin(text) to authenticated;
revoke execute on function public.set_transaction_pin(text) from public, anon;

-- PIN verification remains the only way to create a short-lived authorization session.
-- Session lifetime is intentionally short and is server-checked by the trigger.
notify pgrst, 'reload schema';


-- PATCH: Admin announcement management must NOT require customer transaction PIN.
-- Announcement access is protected by the existing admin permission/RLS policies.
drop trigger if exists aoc_pin_gate_site_announcements on public.site_announcements;

