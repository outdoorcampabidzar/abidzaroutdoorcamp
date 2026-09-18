-- FIX: permission denied for table profiles saat Simpan Profil
-- Jalankan setelah access-security.sql / patch keamanan lain.

revoke update on public.profiles from authenticated;
grant update(full_name, phone, address, city, postal_code, avatar_url)
on public.profiles to authenticated;

notify pgrst, 'reload schema';
