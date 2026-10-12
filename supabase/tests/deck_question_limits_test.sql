-- ---------------------------------------------------------------------------
-- Deck length limits: 12 questions, 8 for Deep Conversations
-- ---------------------------------------------------------------------------
--
-- Pins the trim in 20261113000200 (no active deck over its limit) and the trigger that keeps it
-- that way, whichever route a question takes into a deck: inserted, moved, or switched back on.

begin;
select plan(8);

select is(
  (select count(*)::int from public.game_decks d
   where d.active
     and (select count(*) from (
            select deck_id from public.trivia_questions where active
            union all select deck_id from public.more_likely_prompts where active
            union all select deck_id from public.this_or_that_prompts where active
            union all select deck_id from public.deep_conversation_topics where active) c
          where c.deck_id = d.id) > private.deck_question_limit(d.game_type)),
  0,
  'no active deck holds more questions than its limit'
);

-- Two fresh decks, filled to their limits, so nothing depends on which real decks are full.
insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count)
select 'a1a1a1a1-1313-0000-0000-000000000001', topic, 'this_or_that', 'Limit test: this or that', '🧪', 'plus', 999, true, 0
from public.game_decks where active limit 1;
insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count)
select 'b2b2b2b2-1313-0000-0000-000000000002', topic, 'deep_conversations', 'Limit test: deep', '🧪', 'plus', 999, true, 0
from public.game_decks where active limit 1;

insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id)
select 'A' || i, 'B' || i, true, 'plus', 'Starters', 'a1a1a1a1-1313-0000-0000-000000000001'
from generate_series(1, 12) i;
insert into public.deep_conversation_topics (topic, active, tier, category, deck_id)
select 'Topic ' || i, true, 'plus', 'Starters', 'b2b2b2b2-1313-0000-0000-000000000002'
from generate_series(1, 7) i;

select lives_ok(
  $$insert into public.deep_conversation_topics (topic, active, tier, category, deck_id)
    values ('Topic 8', true, 'plus', 'Starters', 'b2b2b2b2-1313-0000-0000-000000000002')$$,
  'a deck with room takes another question'
);

select throws_ok(
  $$insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id)
    values ('A13', 'B13', true, 'plus', 'Starters', 'a1a1a1a1-1313-0000-0000-000000000001')$$,
  '23514', null,
  'a 13th question is refused'
);

select throws_ok(
  $$insert into public.deep_conversation_topics (topic, active, tier, category, deck_id)
    values ('Topic 9', true, 'plus', 'Starters', 'b2b2b2b2-1313-0000-0000-000000000002')$$,
  '23514', null,
  'a 9th Deep Conversations question is refused'
);

select lives_ok(
  $$insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id)
    values ('A-off', 'B-off', false, 'plus', 'Starters', 'a1a1a1a1-1313-0000-0000-000000000001')$$,
  'a switched-off question can still be filed in a full deck'
);

select throws_ok(
  $$update public.this_or_that_prompts set active = true where option_a = 'A-off'$$,
  '23514', null,
  'but switching it on is refused'
);

insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id)
values ('A-loose', 'B-loose', true, 'plus', 'Starters', null);
select throws_ok(
  $$update public.this_or_that_prompts set deck_id = 'a1a1a1a1-1313-0000-0000-000000000001' where option_a = 'A-loose'$$,
  '23514', null,
  'and so is moving a question into it'
);

-- Editing a question already in a full deck is not adding one.
select lives_ok(
  $$update public.this_or_that_prompts set option_b = 'B1 edited' where option_a = 'A1'
      and deck_id = 'a1a1a1a1-1313-0000-0000-000000000001'$$,
  'editing a question in a full deck still works'
);

select * from finish();
rollback;
