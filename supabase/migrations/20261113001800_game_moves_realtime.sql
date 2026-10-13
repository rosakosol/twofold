-- ============================================================
-- Connect 4 moves arrive live
-- ============================================================
--
-- Reported: a partner's move didn't appear on an open board; leaving the game and coming back was
-- the only way to see it.
--
-- The app subscribes to inserts on game_moves (BackendService.subscribeToGameMoves) and refreshes
-- the board on each one. But Supabase only broadcasts changes for tables in the supabase_realtime
-- publication, and game_moves was never added. game_sessions and game_responses were
-- (20260711020000), which is why every other game updated live. So the subscription connected,
-- waited, and never heard anything: the only thing that reached it was the session row changing
-- when the game ended.
--
-- Realtime applies RLS to what it sends, so a move still reaches only the couple whose board it is
-- (game_moves_select_own_sessions, 20261013000100).
--
-- Guarded so it can run against a database where somebody has already added the table by hand.

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'game_moves'
  ) then
    alter publication supabase_realtime add table public.game_moves;
  end if;
end;
$$;
