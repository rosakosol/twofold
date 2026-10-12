-- The Similarity Check tab scans daily_questions too (added to the Studio in
-- 20261102000000_daily_questions_pool.sql), but this table's content_type check still listed only
-- the original four game types. Every "Not a duplicate" click on a daily-question pair failed the
-- check and the pair stayed put. Widened to the five types the checker actually scans.
alter table public.game_content_duplicate_dismissals
  drop constraint if exists game_content_duplicate_dismissals_content_type_check;

alter table public.game_content_duplicate_dismissals
  add constraint game_content_duplicate_dismissals_content_type_check check (
    content_type in (
      'daily_questions',
      'trivia_questions',
      'more_likely_prompts',
      'this_or_that_prompts',
      'deep_conversation_topics'
    )
  );
