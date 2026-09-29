-- Chess is withdrawn.
--
-- It was the app's only Premium-exclusive whole game, and the most expensive thing in it to keep:
-- roughly a thousand lines of client, a third-party engine, a rules module and a server-side move
-- validator, for one game among five. The two remaining board-and-puzzle games it sat beside are
-- cheaper to own and are moving behind Premium instead.
--
-- Nobody loses anything they paid for. There has never been a paid Premium subscription — the only
-- Premium entitlements in this project are promotional grants made for App Review — so this is the
-- cheapest moment it will ever be withdrawn.

-- The sessions, and everything hanging off them.
--
-- `game_session_rounds`, `game_responses`, `game_moves` and `game_turn_notices` all cascade from
-- `game_sessions`, so this one delete is the whole cleanup. Deleted rather than archived because
-- the Swift `GameType` loses its `chess` case in the same change: an archived row would still be
-- fetched by history and stats and would fail to decode, which is worse than not being there.
delete from public.game_sessions where game_type = 'chess';

-- The only way to make another one.
drop function if exists public.start_chess_session();

-- The `chess` label stays in the `game_type` enum, deliberately.
--
-- Postgres has no `alter type ... drop value`. Removing it means building a replacement type and
-- rewriting every column, index, constraint and function that names the old one — across
-- `game_sessions`, `game_content`, the stats views and a dozen RPCs. That is a large, risky
-- migration whose entire benefit is that one unused label stops appearing in `\dT+`.
--
-- Leaving it is safe: with the function above gone there is no path that can write it, and with
-- the rows above gone there is nothing to read. If the type is ever rebuilt for another reason,
-- drop the label then.
comment on type public.game_type is
  'Game kinds. The `chess` label is retired and unused — see 20261111000600. Postgres cannot drop '
  'an enum value without recreating the type, so it remains as a tombstone; nothing writes it.';
