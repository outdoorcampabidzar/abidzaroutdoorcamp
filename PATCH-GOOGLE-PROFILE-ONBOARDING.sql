-- AOC: Google OAuth wajib melengkapi profil + PIN sebelum masuk aplikasi.
-- Jalankan setelah PATCH-TRANSACTION-PIN-SECURITY.sql / PATCH-PIN-SECURITY-ALL-SENSITIVE.sql.

alter table public.profiles add column if not exists username text;
alter table public.profiles add column if not exists identity_type text;
alter table public.profiles add column if not exists identity_last4 text;
alter table public.profiles add column if not exists emergency_contact_name text;
alter table public.profiles add column if not exists emergency_contact_phone text;

create unique index if not exists profiles_username_lower_uidx on public.profiles(lower(username)) where username is not null;

create or replace function public.complete_google_profile(p_profile jsonb, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = public, private
as $$
declare v_user uuid := auth.uid(); v_pin text := regexp_replace(coalesce(p_pin,''),'\\D','','g');
begin
 if v_user is null then raise exception 'Sesi login tidak ditemukan.'; end if;
 if length(v_pin) <> 6 then raise exception 'PIN harus tepat 6 digit.'; end if;
 if v_pin ~ '^(.)\\1{5}$' then raise exception 'PIN tidak boleh semua angkanya sama.'; end if;
 if nullif(trim(p_profile->>'username'),'') is null then raise exception 'Username wajib diisi.'; end if;
 if length(trim(p_profile->>'username')) < 3 or length(trim(p_profile->>'username')) > 30 then raise exception 'Username harus 3-30 karakter.'; end if;
 if trim(p_profile->>'identity_type') not in ('KTP','SIM','PASPOR') then raise exception 'Jenis identitas tidak valid.'; end if;
 if trim(p_profile->>'identity_last4') !~ '^\\d{4}$' then raise exception '4 digit terakhir identitas wajib diisi.'; end if;
 if nullif(trim(p_profile->>'full_name'),'') is null or nullif(trim(p_profile->>'phone'),'') is null or nullif(trim(p_profile->>'city'),'') is null or nullif(trim(p_profile->>'address'),'') is null then raise exception 'Data profil wajib belum lengkap.'; end if;
 if nullif(trim(p_profile->>'emergency_contact_name'),'') is null or nullif(trim(p_profile->>'emergency_contact_phone'),'') is null then raise exception 'Kontak darurat wajib diisi.'; end if;
 if exists(select 1 from public.profiles where lower(username)=lower(trim(p_profile->>'username')) and id<>v_user) then raise exception 'Username sudah digunakan.'; end if;
 update public.profiles set username=trim(p_profile->>'username'),full_name=trim(p_profile->>'full_name'),phone=trim(p_profile->>'phone'),city=trim(p_profile->>'city'),address=trim(p_profile->>'address'),postal_code=nullif(trim(p_profile->>'postal_code'),''),identity_type=trim(p_profile->>'identity_type'),identity_last4=trim(p_profile->>'identity_last4'),emergency_contact_name=trim(p_profile->>'emergency_contact_name'),emergency_contact_phone=trim(p_profile->>'emergency_contact_phone'),updated_at=now() where id=v_user;
 if not found then insert into public.profiles(id,username,full_name,phone,city,address,postal_code,identity_type,identity_last4,emergency_contact_name,emergency_contact_phone,role) values(v_user,trim(p_profile->>'username'),trim(p_profile->>'full_name'),trim(p_profile->>'phone'),trim(p_profile->>'city'),trim(p_profile->>'address'),nullif(trim(p_profile->>'postal_code'),''),trim(p_profile->>'identity_type'),trim(p_profile->>'identity_last4'),trim(p_profile->>'emergency_contact_name'),trim(p_profile->>'emergency_contact_phone'),'user'); end if;
 perform public.set_transaction_pin(v_pin);
 return jsonb_build_object('success',true,'profile_complete',true,'pin_set',true);
end; $$;
revoke all on function public.complete_google_profile(jsonb,text) from public, anon;
grant execute on function public.complete_google_profile(jsonb,text) to authenticated;
