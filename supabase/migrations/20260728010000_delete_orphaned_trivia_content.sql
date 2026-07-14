-- Follow-up to 20260728000000 — the user decided against building further Trivia decks from
-- the orphaned pool, so it gets the same cleanup the other three game types already got: remove
-- rows never tagged to an active deck (untagged, or tagged to a deprecated deck).
delete from public.trivia_questions
where active and (deck_id is null or deck_id in (select id from public.game_decks where not active));
