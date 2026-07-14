-- Removes orphaned content rows (never tagged to an active deck — either never deck-tagged at
-- all, or tagged to one of the deprecated decks from 20260719000000) for This or That, More
-- Likely, and Discuss. These three have no more spare content worth surfacing as new decks (see
-- 20260726000000/20260727000000 batches), so the leftover rows are just dead weight sitting in
-- the random shared-pool quick-play rotation. Trivia is deliberately left untouched — more
-- Trivia decks are still planned from its orphaned pool.
delete from public.this_or_that_prompts
where active and (deck_id is null or deck_id in (select id from public.game_decks where not active));

delete from public.more_likely_prompts
where active and (deck_id is null or deck_id in (select id from public.game_decks where not active));

delete from public.discussion_topics
where active and (deck_id is null or deck_id in (select id from public.game_decks where not active));
