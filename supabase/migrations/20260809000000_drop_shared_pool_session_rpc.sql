-- Removes the shared-pool session RPC. Every game session is now started from a specific,
-- curated deck via start_deck_session — there's no more "random draw across every topic for
-- this game type" entry point anywhere in the app (GameEntryView, its Swift-side caller, is
-- deleted alongside this).
drop function if exists public.start_game_session(game_type);
