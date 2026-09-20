-- `game_decks.question_count` agrees with the rows it counts, and goes on agreeing.
--
-- Two separate claims, and the second is the one that matters long-term. 20261031000000 corrected
-- 36 decks that had drifted; that is a one-off. What stops it happening again is the per-table
-- triggers from 20260830001000, and nothing pinned those — which is how the column could be wrong
-- for months with every test passing.
--
-- Worth being precise about why a wrong count is not cosmetic. `LocalGameSessionStore.create` takes
-- `totalRounds` from this column when building an offline session, so a deck claiming more
-- questions than it holds produces a session that cannot reach its own end.

begin;
select plan(11);

create extension if not exists pgtap;

-- ---------------------------------------------------------------------------
-- The state the reconcile migration leaves behind
-- ---------------------------------------------------------------------------

-- Uses `private.deck_content_count` rather than restating the game-type-to-table mapping. A test
-- carrying its own copy of the thing under test can only ever agree with itself, and a second copy
-- of that mapping is what this whole area went wrong on.

select is(
  (select count(*)::int from public.game_decks d where d.question_count is distinct from private.deck_content_count(d.id, d.game_type)),
  0,
  'every deck''s question_count matches the rows it counts'
);

-- The CASE above is exhaustive only while these are the only content-backed types. A fifth one
-- added without extending it would make `actual_count` null, and the assertion above would pass for
-- the wrong reason — null is distinct from a number, so it would fail, but this says why.
select is(
  (select count(*)::int from public.game_decks d where private.deck_content_count(d.id, d.game_type) is null),
  0,
  'no deck has a game type deck_content_count cannot count'
);

-- The harmful direction, called out on its own: a deck promising rounds it cannot serve.
select is(
  (select count(*)::int from public.game_decks d where d.question_count > private.deck_content_count(d.id, d.game_type)),
  0,
  'no deck advertises more questions than it holds'
);

-- ---------------------------------------------------------------------------
-- The triggers that keep it that way, one content table at a time
-- ---------------------------------------------------------------------------

-- trivia
create temp table t_deck as
select id from public.game_decks where game_type = 'trivia_battle' limit 1;

select is(
  (select question_count from public.game_decks where id = (select id from t_deck)),
  (select private.deck_content_count(id, game_type)::int from public.game_decks where id = (select id from t_deck)),
  'trivia deck starts consistent'
);

insert into public.trivia_questions (id, deck_id, category, question, options, correct_answer, difficulty)
values ('11110000-0000-4000-8000-000000000001', (select id from t_deck), 'Test', 'Q?',
        '["a","b"]'::jsonb, 'a', 'easy');

select is(
  (select question_count from public.game_decks where id = (select id from t_deck)),
  (select private.deck_content_count(id, game_type)::int from public.game_decks where id = (select id from t_deck)),
  'inserting a trivia question moves the count with it'
);

delete from public.trivia_questions where id = '11110000-0000-4000-8000-000000000001';

select is(
  (select question_count from public.game_decks where id = (select id from t_deck)),
  (select private.deck_content_count(id, game_type)::int from public.game_decks where id = (select id from t_deck)),
  'deleting it moves the count back'
);

-- more likely
create temp table m_deck as
select id from public.game_decks where game_type = 'more_likely' limit 1;

insert into public.more_likely_prompts (id, deck_id, category, prompt)
values ('11110000-0000-4000-8000-000000000002', (select id from m_deck), 'Test', 'Who?');

select is(
  (select question_count from public.game_decks where id = (select id from m_deck)),
  (select private.deck_content_count(id, game_type)::int from public.game_decks where id = (select id from m_deck)),
  'inserting a more-likely prompt moves the count'
);

delete from public.more_likely_prompts where id = '11110000-0000-4000-8000-000000000002';

-- this or that
create temp table x_deck as
select id from public.game_decks where game_type = 'this_or_that' limit 1;

insert into public.this_or_that_prompts (id, deck_id, category, option_a, option_b)
values ('11110000-0000-4000-8000-000000000003', (select id from x_deck), 'Test', 'A', 'B');

select is(
  (select question_count from public.game_decks where id = (select id from x_deck)),
  (select private.deck_content_count(id, game_type)::int from public.game_decks where id = (select id from x_deck)),
  'inserting a this-or-that prompt moves the count'
);

delete from public.this_or_that_prompts where id = '11110000-0000-4000-8000-000000000003';

-- deep conversations
create temp table d_deck as
select id from public.game_decks where game_type = 'deep_conversations' limit 1;

insert into public.deep_conversation_topics (id, deck_id, category, topic)
values ('11110000-0000-4000-8000-000000000004', (select id from d_deck), 'Test', 'Tell me about...');

select is(
  (select question_count from public.game_decks where id = (select id from d_deck)),
  (select private.deck_content_count(id, game_type)::int from public.game_decks where id = (select id from d_deck)),
  'inserting a deep-conversation topic moves the count'
);

delete from public.deep_conversation_topics where id = '11110000-0000-4000-8000-000000000004';

-- Moving a row between decks has to move the count at both ends. The trigger fires on
-- `update of deck_id` for exactly this, and getting only the new deck right would leave the old one
-- overstating — the same direction as the drift this all started with.
create temp table t_deck2 as
select id from public.game_decks where game_type = 'trivia_battle' and id <> (select id from t_deck) limit 1;

insert into public.trivia_questions (id, deck_id, category, question, options, correct_answer, difficulty)
values ('11110000-0000-4000-8000-000000000005', (select id from t_deck), 'Test', 'Q?',
        '["a","b"]'::jsonb, 'a', 'easy');
update public.trivia_questions set deck_id = (select id from t_deck2)
where id = '11110000-0000-4000-8000-000000000005';

select is(
  (select question_count from public.game_decks where id = (select id from t_deck)),
  (select private.deck_content_count(id, game_type)::int from public.game_decks where id = (select id from t_deck)),
  'moving a question away leaves the old deck correct'
);
select is(
  (select question_count from public.game_decks where id = (select id from t_deck2)),
  (select private.deck_content_count(id, game_type)::int from public.game_decks where id = (select id from t_deck2)),
  'and the new deck correct'
);

select * from finish();
rollback;
