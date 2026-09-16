-- AOC - Storage Logo Header
-- Jalankan sekali di Supabase SQL Editor setelah access-security.sql.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('site-assets', 'site-assets', true, 2097152, array['image/png','image/jpeg','image/webp','image/svg+xml'])
on conflict (id) do update set
  public = true,
  file_size_limit = 2097152,
  allowed_mime_types = array['image/png','image/jpeg','image/webp','image/svg+xml'];

drop policy if exists "site assets public read" on storage.objects;
drop policy if exists "site assets admin insert" on storage.objects;
drop policy if exists "site assets admin update" on storage.objects;
drop policy if exists "site assets admin delete" on storage.objects;

create policy "site assets public read"
on storage.objects for select
using (bucket_id = 'site-assets');

create policy "site assets admin insert"
on storage.objects for insert to authenticated
with check (bucket_id = 'site-assets' and (public.has_permission('settings.manage') or public.has_permission('*')));

create policy "site assets admin update"
on storage.objects for update to authenticated
using (bucket_id = 'site-assets' and (public.has_permission('settings.manage') or public.has_permission('*')))
with check (bucket_id = 'site-assets' and (public.has_permission('settings.manage') or public.has_permission('*')));

create policy "site assets admin delete"
on storage.objects for delete to authenticated
using (bucket_id = 'site-assets' and (public.has_permission('settings.manage') or public.has_permission('*')));
