create or replace function public.debug_topic_counts()
returns table(tier text, active_count bigint)
language sql security definer set search_path = public as $$
  select tier, count(*) from public.deep_conversation_topics where active group by tier;
$$;
grant execute on function public.debug_topic_counts() to anon, authenticated;
