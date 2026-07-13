-- Reverts 20260717050000_game_responses_update_own.sql — the back/forward round navigator that
-- motivated this UPDATE policy was removed before shipping, and submitGameResponse is a plain
-- insert again, so no code path exercises this policy anymore.
drop policy if exists "game_responses_update_own_active" on public.game_responses;
