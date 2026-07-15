-- edit_my_game_responses (20260716000000/20260717000000) is no longer called — "Edit My
-- Answers" now just rewinds the client's viewingRoundNumber to round 1 and lets the existing
-- upsert-on-submit path overwrite each round in place (see GameSessionStore.beginEditingAnswers),
-- so nothing needs to delete responses or reset the session's status server-side anymore.
drop function if exists public.edit_my_game_responses(uuid);
