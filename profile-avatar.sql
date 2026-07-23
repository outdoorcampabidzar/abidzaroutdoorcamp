-- FOTO PROFIL PENGGUNA DAN AVATAR ULASAN
-- Jalankan seluruh file ini melalui Supabase SQL Editor.

alter table public.profiles
  add column if not exists avatar_url text;

grant select on public.profiles to authenticated;
grant update(avatar_url) on public.profiles to authenticated;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'avatars',
  'avatars',
  true,
  3145728,
  array['image/jpeg','image/png','image/webp']
)
on conflict (id) do update set
  public = true,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "avatars public read" on storage.objects;
create policy "avatars public read"
on storage.objects for select
using (bucket_id = 'avatars');

drop policy if exists "users upload own avatar" on storage.objects;
create policy "users upload own avatar"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "users update own avatar" on storage.objects;
create policy "users update own avatar"
on storage.objects for update
to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "users delete own avatar" on storage.objects;
create policy "users delete own avatar"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- Return type bertambah avatar_url, sehingga fungsi lama harus dihapus dahulu.
drop function if exists public.get_website_reviews(integer);

create function public.get_website_reviews(p_limit integer default 6)
returns table(
  display_name text,
  avatar_url text,
  score integer,
  comment text,
  created_at timestamptz,
  updated_at timestamptz,
  is_mine boolean,
  total_count bigint
)
language sql
stable
security definer
set search_path = public, auth
as $$
  with visible as (
    select
      case
        when nullif(trim(coalesce(p.full_name, '')), '') is not null
          then split_part(trim(p.full_name), ' ', 1)
        else 'Pengguna'
      end::text as display_name,
      p.avatar_url::text,
      wr.score,
      (
        coalesce(wr.comment, '') ||
        case
          when nullif(trim(coalesce(wr.admin_reply, '')), '') is not null
            then E'\n\nBalasan admin: ' || wr.admin_reply
          else ''
        end
      )::text as comment,
      wr.created_at,
      wr.updated_at,
      (wr.user_id = auth.uid()) as is_mine,
      count(*) over() as total_count
    from public.website_ratings wr
    left join public.profiles p on p.id = wr.user_id
    where coalesce(wr.is_hidden, false) = false
      and nullif(trim(coalesce(wr.comment, '')), '') is not null
    order by
      case when wr.user_id = auth.uid() then 0 else 1 end,
      wr.updated_at desc
  )
  select *
  from visible
  limit greatest(1, least(coalesce(p_limit, 6), 30));
$$;

revoke all on function public.get_website_reviews(integer) from public;
grant execute on function public.get_website_reviews(integer)
  to anon, authenticated;

notify pgrst, 'reload schema';
