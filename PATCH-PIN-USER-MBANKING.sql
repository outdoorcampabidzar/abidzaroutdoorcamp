-- AOC USER TRANSACTION PIN - mBANKING STYLE
-- User creates PIN only for their own account.
-- Existing PIN can only be changed after verifying the old PIN.
-- Admins cannot read or set a customer's PIN through these functions.

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
  if v_pin ~ '^(.)\1{5}$' then raise exception 'PIN tidak boleh semua angkanya sama.'; end if;

  select exists(select 1 from private.aoc_transaction_pins where user_id=v_user_id) into v_exists;
  if v_exists then
    raise exception 'PIN sudah dibuat. Untuk mengganti PIN, verifikasi PIN lama terlebih dahulu.';
  end if;

  insert into private.aoc_transaction_pins(user_id,pin_hash,failed_attempts,locked_until,updated_at)
  values(v_user_id, extensions.crypt(v_pin, extensions.gen_salt('bf',10)),0,null,now());
  delete from private.aoc_transaction_pin_sessions where user_id=v_user_id;
  return jsonb_build_object('success',true,'message','PIN transaksi berhasil dibuat.');
end;
$$;

create or replace function public.change_transaction_pin(p_current_pin text, p_new_pin text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_old text := trim(coalesce(p_current_pin,''));
  v_new text := trim(coalesce(p_new_pin,''));
  v_row private.aoc_transaction_pins%rowtype;
begin
  if v_user_id is null then raise exception 'Silakan login terlebih dahulu'; end if;
  if v_old !~ '^\d{6}$' or v_new !~ '^\d{6}$' then raise exception 'PIN harus tepat 6 digit.'; end if;
  if v_new ~ '^(.)\1{5}$' then raise exception 'PIN baru tidak boleh semua angkanya sama.'; end if;
  if v_old = v_new then raise exception 'PIN baru harus berbeda dari PIN lama.'; end if;

  select * into v_row from private.aoc_transaction_pins where user_id=v_user_id for update;
  if not found then raise exception 'PIN transaksi belum dibuat. Gunakan fitur Buat PIN terlebih dahulu.'; end if;
  if v_row.locked_until is not null and v_row.locked_until > now() then
    raise exception 'PIN terkunci sementara karena terlalu banyak percobaan salah.';
  end if;

  if extensions.crypt(v_old,v_row.pin_hash) <> v_row.pin_hash then
    update private.aoc_transaction_pins
      set failed_attempts=failed_attempts+1,
          locked_until=case when failed_attempts+1 >= 5 then now()+interval '15 minutes' else null end,
          updated_at=now()
      where user_id=v_user_id;
    raise exception 'PIN lama salah.';
  end if;

  update private.aoc_transaction_pins
    set pin_hash=extensions.crypt(v_new,extensions.gen_salt('bf',10)),
        failed_attempts=0, locked_until=null, updated_at=now()
    where user_id=v_user_id;
  delete from private.aoc_transaction_pin_sessions where user_id=v_user_id;
  return jsonb_build_object('success',true,'message','PIN transaksi berhasil diganti.');
end;
$$;

revoke all on function public.set_transaction_pin(text) from public,anon;
revoke all on function public.change_transaction_pin(text,text) from public,anon;
grant execute on function public.set_transaction_pin(text) to authenticated;
grant execute on function public.change_transaction_pin(text,text) to authenticated;
notify pgrst,'reload schema';
