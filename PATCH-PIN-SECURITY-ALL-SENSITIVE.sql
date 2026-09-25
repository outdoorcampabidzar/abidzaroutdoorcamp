-- AOC SECURITY HARDENING: TRANSACTION PIN FOR SENSITIVE MUTATIONS
-- Run AFTER PATCH-TRANSACTION-PIN-SECURITY.sql and AFTER the base schema.
-- PIN is never stored in plaintext. Sensitive writes require a fresh server-side PIN session.

create extension if not exists pgcrypto with schema extensions;
create schema if not exists private;

-- Harden the existing PIN setter: an existing PIN cannot be silently replaced
-- by a logged-in session without proving the current PIN first.
create or replace function public.set_transaction_pin(p_pin text, p_current_pin text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_pin text := trim(coalesce(p_pin, ''));
  v_current text := trim(coalesce(p_current_pin, ''));
  v_existing_hash text;
begin
  if v_user_id is null then raise exception 'Silakan login terlebih dahulu'; end if;
  if v_pin !~ '^\d{6}$' then raise exception 'PIN transaksi harus tepat 6 digit.'; end if;
  if v_pin !~ '^(?!([0-9])\1{5})\d{6}$' then raise exception 'PIN tidak boleh 6 angka yang sama.'; end if;

  select pin_hash into v_existing_hash
  from private.aoc_transaction_pins
  where user_id=v_user_id;

  if v_existing_hash is not null then
    if v_current !~ '^\d{6}$' or extensions.crypt(v_current, v_existing_hash) <> v_existing_hash then
      raise exception 'PIN lama wajib benar untuk mengganti PIN.';
    end if;
  end if;

  insert into private.aoc_transaction_pins(user_id,pin_hash,failed_attempts,locked_until,updated_at)
  values(v_user_id,extensions.crypt(v_pin,extensions.gen_salt('bf',10)),0,null,now())
  on conflict(user_id) do update set
    pin_hash=excluded.pin_hash, failed_attempts=0, locked_until=null, updated_at=now();

  delete from private.aoc_transaction_pin_sessions where user_id=v_user_id;
  return jsonb_build_object('success',true,'message','PIN transaksi berhasil disimpan.');
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
    'inventory_units','aoc_locations','shop_rewards','coin_settings','site_announcements',
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

grant execute on function public.set_transaction_pin(text,text) to authenticated;
revoke execute on function public.set_transaction_pin(text) from public, anon;

-- PIN verification remains the only way to create a short-lived authorization session.
-- Session lifetime is intentionally short and is server-checked by the trigger.
notify pgrst, 'reload schema';
