-- Removes every inactive game_decks row and everything that references it.
-- 5 sessions (all dated 2026-07-13, dev/test play) still pointed at inactive decks —
-- deleted along with their rounds/responses since NO ACTION FKs would otherwise block
-- the deck deletes below.

delete from game_responses
where session_id in (
  select gs.id from game_sessions gs
  join game_decks gd on gd.id = gs.deck_id
  where gd.active = false
);

delete from game_session_rounds
where session_id in (
  select gs.id from game_sessions gs
  join game_decks gd on gd.id = gs.deck_id
  where gd.active = false
);

delete from game_sessions
where deck_id in (select id from game_decks where active = false);

delete from this_or_that_prompts
where deck_id in (select id from game_decks where active = false);

delete from more_likely_prompts
where deck_id in (select id from game_decks where active = false);

delete from trivia_questions
where deck_id in (select id from game_decks where active = false);

delete from discussion_topics
where deck_id in (select id from game_decks where active = false);

delete from game_decks
where active = false;
