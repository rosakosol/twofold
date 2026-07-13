-- Stored (not dynamically computed) question count per deck — content is polymorphic across 4
-- separate tables depending on game_type, so a live join/view isn't a single simple query. A
-- snapshot is fine here since decks are curated/admin-authored content, not something that
-- changes on its own; the same tradeoff game_sessions.total_rounds already makes.

alter table public.game_decks add column question_count int not null default 0;

update public.game_decks d set question_count = (
  case d.game_type
    when 'travel_trivia' then (select count(*) from public.trivia_questions where deck_id = d.id)
    when 'more_likely' then (select count(*) from public.more_likely_prompts where deck_id = d.id)
    when 'this_or_that' then (select count(*) from public.this_or_that_prompts where deck_id = d.id)
    when 'discuss_before_travelling' then (select count(*) from public.discussion_topics where deck_id = d.id)
  end
);
