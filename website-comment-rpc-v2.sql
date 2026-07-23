-- PERBAIKAN RATING DAN KOMENTAR WEBSITE
-- Jalankan seluruh file ini di Supabase SQL Editor.

alter table public.website_ratings
  add column if not exists comment text;
alter table public.website_ratings
  add column if not exists is_hidden boolean not null default false;

create unique index if not exists website_ratings_user_unique
  on public.website_ratings(user_id);

create or replace function public.save_website_review_v2(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_score integer;
  v_input_comment text;
  v_existing_comment text;
  v_saved_comment text;
  v_average numeric := 0;
  v_count bigint := 0;
begin
  if v_user_id is null then
    raise exception 'Silakan login untuk memberikan rating website';
  end if;

  begin
    v_score := (p_payload ->> 'score')::integer;
  exception
    when others then
      raise exception 'Nilai rating tidak valid';
  end;

  if v_score is null or v_score < 1 or v_score > 5 then
    raise exception 'Rating harus antara 1 sampai 5 bintang';
  end if;

  v_input_comment :=
    nullif(trim(coalesce(p_payload ->> 'comment', '')), '');

  if v_input_comment is not null
     and char_length(v_input_comment) > 300 then
    raise exception 'Komentar maksimal 300 karakter';
  end if;

  select wr.comment
    into v_existing_comment
  from public.website_ratings wr
  where wr.user_id = v_user_id
  limit 1;

  if v_input_comment is null and v_existing_comment is null then
    raise exception 'Komentar wajib diisi agar ulasan dapat ditampilkan';
  end if;

  -- Jika input komentar kosong, komentar lama tidak dihapus.
  v_saved_comment := coalesce(v_input_comment, v_existing_comment);

  insert into public.website_ratings (
    user_id,
    score,
    comment,
    created_at,
    updated_at
  )
  values (
    v_user_id,
    v_score,
    v_saved_comment,
    now(),
    now()
  )
  on conflict (user_id)
  do update set
    score = excluded.score,
    comment = coalesce(
      excluded.comment,
      public.website_ratings.comment
    ),
    updated_at = now();

  select wr.comment
    into v_saved_comment
  from public.website_ratings wr
  where wr.user_id = v_user_id
  limit 1;

  select
    coalesce(round(avg(wr.score)::numeric, 1), 0),
    count(*)
  into v_average, v_count
  from public.website_ratings wr
  where coalesce(wr.is_hidden, false) = false;

  return jsonb_build_object(
    'success', true,
    'rating_average', v_average,
    'rating_count', v_count,
    'my_score', v_score,
    'my_comment', coalesce(v_saved_comment, '')
  );
end;
$$;

create or replace function public.submit_website_rating(
  p_score integer,
  p_comment text default null
)
returns jsonb
language sql
security definer
set search_path = public, auth
as $$
  select public.save_website_review_v2(
    jsonb_build_object(
      'score', p_score,
      'comment', p_comment
    )
  );
$$;

revoke all on function public.save_website_review_v2(jsonb) from public;
revoke all on function public.submit_website_rating(integer, text) from public;
grant execute on function public.save_website_review_v2(jsonb) to authenticated;
grant execute on function public.submit_website_rating(integer, text) to authenticated;

notify pgrst, 'reload schema';

-- Pemeriksaan: comment seharusnya berisi teks, bukan NULL,
-- setelah pengguna mengirim rating dan komentar lagi.
select user_id, score, comment, is_hidden, updated_at
from public.website_ratings
order by updated_at desc;
