-- V64: fix Data Anggota save/photo storage
insert into storage.buckets (id, name, public)
values ('member-photos', 'member-photos', true)
on conflict (id) do update set public = true;

drop policy if exists "member photos admin insert" on storage.objects;
drop policy if exists "member photos admin update" on storage.objects;
drop policy if exists "member photos admin delete" on storage.objects;
drop policy if exists "member photos public read" on storage.objects;

create policy "member photos public read"
on storage.objects for select to public
using (bucket_id = 'member-photos');

create policy "member photos admin insert"
on storage.objects for insert to authenticated
with check (bucket_id = 'member-photos' and public.is_admin());

create policy "member photos admin update"
on storage.objects for update to authenticated
using (bucket_id = 'member-photos' and public.is_admin())
with check (bucket_id = 'member-photos' and public.is_admin());

create policy "member photos admin delete"
on storage.objects for delete to authenticated
using (bucket_id = 'member-photos' and public.is_admin());

grant execute on function public.secure_admin_upsert_member_id_card(uuid,jsonb) to authenticated;
grant execute on function public.get_public_member_id_card(text) to anon, authenticated;
