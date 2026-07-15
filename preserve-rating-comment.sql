-- PERBAIKAN KOMENTAR RATING WEBSITE
-- Kolom komentar kosong tidak lagi menghapus komentar lama.
-- Jalankan seluruh file ini melalui Supabase SQL Editor.

create or replace function public.submit_website_rating(
  p_score integer,
  p_comment text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_input_comment text;
  v_saved_comment text;
  v_average numeric := 0;
  v_count bigint := 0;
begin
  if v_user_id is null then
    raise exception 'Silakan login untuk memberikan rating website';
  end if;

  if p_score is null or p_score < 1 or p_score > 5 then
    raise exception 'Rating harus antara 1 sampai 5 bintang';
  end if;

  v_input_comment := nullif(trim(coalesce(p_comment, '')), '');

  if v_input_comment is not null
     and char_length(v_input_comment) > 300 then
    raise exception 'Komentar maksimal 300 karakter';
  end if;

  select wr.comment
  into v_saved_comment
  from public.website_ratings wr
  where wr.user_id = v_user_id
  limit 1;

  -- Input kosong mempertahankan komentar sebelumnya.
  v_saved_comment := coalesce(v_input_comment, v_saved_comment);

  insert into public.website_ratings (
    user_id,
    score,
    comment,
    updated_at
  )
  values (
    v_user_id,
    p_score,
    v_saved_comment,
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
  into
    v_average,
    v_count
  from public.website_ratings wr;

  return jsonb_build_object(
    'rating_average', v_average,
    'rating_count', v_count,
    'my_score', p_score,
    'my_comment', coalesce(v_saved_comment, '')
  );
end;
$$;

revoke all on function public.submit_website_rating(integer, text)
from public;

grant execute on function public.submit_website_rating(integer, text)
to authenticated;

notify pgrst, 'reload schema';

select
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as arguments
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'submit_website_rating';
