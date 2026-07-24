-- Powers the "Popular this week" widget: features with the most votes cast in the
-- trailing 7 days, not just highest all-time upvote_count. Plain (non security-definer)
-- SQL function — it runs with the caller's own privileges, so it's already governed by
-- feature_votes/feature_requests' existing public-select RLS policies.
create or replace function public.popular_this_week(result_limit int default 5)
returns table (
  id uuid,
  title text,
  slug text,
  status public.feedback_request_status,
  upvote_count int,
  recent_votes bigint
)
language sql
stable
as $$
  select fr.id, fr.title, fr.slug, fr.status, fr.upvote_count, v.recent_votes
  from public.feature_requests fr
  join (
    select feature_id, count(*) as recent_votes
    from public.feature_votes
    where created_at >= now() - interval '7 days'
    group by feature_id
  ) v on v.feature_id = fr.id
  where fr.merged_into is null
  order by v.recent_votes desc
  limit result_limit;
$$;

grant execute on function public.popular_this_week(int) to anon, authenticated;
