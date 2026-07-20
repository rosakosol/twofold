-- Powers "Did you mean: X (128 votes)?" duplicate-suggestion UI while a user types a
-- new request title. Uses the trigram index on feature_requests.title (see
-- 20260719000400_feature_requests.sql) via pg_trgm's similarity() function.
--
-- Plain `language sql` (no security definer) — feature_requests is already fully
-- public-readable via RLS, so this just runs as whatever role calls it.
create or replace function public.search_similar_feature_requests(query text, match_limit int default 5)
returns table (
  id uuid,
  title text,
  slug text,
  upvote_count int,
  status public.feedback_request_status,
  similarity real
)
language sql
stable
set search_path = public
as $$
  select
    id, title, slug, upvote_count, status,
    similarity(title, query) as similarity
  from public.feature_requests
  where merged_into is null
    and similarity(title, query) > 0.2
  order by similarity(title, query) desc
  limit match_limit;
$$;

grant execute on function public.search_similar_feature_requests(text, int) to anon, authenticated;
