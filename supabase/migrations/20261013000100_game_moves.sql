-- ---------------------------------------------------------------------------
-- Moves: the first game state this app has had
-- ---------------------------------------------------------------------------
--
-- Every game until now has been content. A sudoku, a word, a grid of letters — you fetch one, both
-- of you answer it independently, and the answers are compared. Nothing changes underneath anyone.
--
-- Connect 4 is a position that evolves, and both players write to it alternately. That needs three
-- things none of the existing games do: somewhere to keep the moves, a rule about whose turn it is
-- that the *server* enforces, and a way for each device to hear about a move as it happens.
--
-- ---------------------------------------------------------------------------
-- Why the turn has to be a database constraint
-- ---------------------------------------------------------------------------
--
-- Not because anybody is cheating. Because of the race: both partners' phones hold the same board,
-- and if whose-turn-it-is is decided on the device then two moves sent within the same moment both
-- believe they are legal. There is no later point at which that can be resolved — the board has
-- forked, and each player is looking at a real, self-consistent game the other one is not playing.
--
-- So `move_number` is unique per session. Two moves racing for the same number is not a judgement
-- call about which arrived first; it is a unique violation, and exactly one of them survives. The
-- turn check inside `play_connect_four_move` is what produces a *useful error* for the loser of
-- that race; this index is what makes the outcome correct regardless.
--
-- This is a different question from whether a move is legal, which stays on the device (see the
-- games plan). A dropped disc has one rule and both clients apply it; a forked board has no rule
-- at all.
--
-- ---------------------------------------------------------------------------
-- Append-only
-- ---------------------------------------------------------------------------
--
-- No update, no delete, for anybody. The board is derived by replaying this table in order, so a
-- move that could be edited afterwards is a board that can change behind the player who is looking
-- at it — and an undo in a two-player game is the other person's move being taken back.
--
-- `move` is text rather than an integer, deliberately. Connect 4 writes a column ("3") and chess
-- will write something like "e2e4q". Both are one opaque token per move to everything here except
-- the function that understands that game, which is what keeps this table from growing a column
-- per game.

create table if not exists public.game_moves (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.game_sessions(id) on delete cascade,
  -- 0-based, and the ordering that defines the game. Unique per session: see above.
  move_number int not null check (move_number >= 0),
  player_id uuid not null references public.profiles(id),
  move text not null check (length(move) between 1 and 16),
  created_at timestamptz not null default now(),
  unique (session_id, move_number)
);

create index if not exists game_moves_session_idx
  on public.game_moves (session_id, move_number);

alter table public.game_moves enable row level security;

-- Readable by whoever can see the session it belongs to: either partner of the couple, or the
-- initiator of a solo session. Mirrors `game_session_rounds`' own policy rather than inventing a
-- second shape of the same rule.
--
-- Deliberately *not* hidden until both have played, the way `game_responses` is. That secrecy
-- exists so one partner's answer cannot spoil the other's; here the whole point is that both of
-- them are looking at the same board.
drop policy if exists "game_moves_select_own_sessions" on public.game_moves;
create policy "game_moves_select_own_sessions" on public.game_moves
  for select using (
    exists (
      select 1 from public.game_sessions gs
      where gs.id = game_moves.session_id
        and (
          (gs.couple_id is not null and public.is_couple_member(gs.couple_id))
          or (gs.couple_id is null and gs.initiator_id = auth.uid())
        )
    )
  );

-- No insert, update or delete policy at all. Every write goes through
-- `play_connect_four_move`, which is `security definer` — so the turn rule cannot be bypassed by
-- writing to this table directly, which is the entire reason the rule is here rather than on the
-- device.
revoke insert, update, delete on public.game_moves from anon, authenticated;

comment on table public.game_moves is
  'Append-only move log for turn-based games. The board is derived by replaying it in order. '
  'Written only by the per-game move RPCs (security definer); clients may read but never write.';
