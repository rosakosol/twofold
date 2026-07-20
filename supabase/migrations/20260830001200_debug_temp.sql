create or replace function public.debug_game_content_setup()
returns table(policy_count bigint, trigger_count bigint)
language sql security definer set search_path = public as $$
  select
    (select count(*) from pg_policies where schemaname = 'public' and policyname like '%_admin_write'
      and tablename in ('trivia_questions','more_likely_prompts','this_or_that_prompts','deep_conversation_topics','game_decks')),
    (select count(*) from pg_trigger where tgname like '%_deck_count' and not tgisinternal);
$$;
grant execute on function public.debug_game_content_setup() to anon, authenticated;
