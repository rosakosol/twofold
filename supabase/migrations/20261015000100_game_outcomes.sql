-- ---------------------------------------------------------------------------
-- Recording how a game ended, rather than working it out again later
-- ---------------------------------------------------------------------------
--
-- Connect 4 and chess both decide a winner and then throw the answer away: the move that ends the
-- game sets `status = 'completed'` and nothing else. The result was always recoverable for Connect
-- 4 — replay the discs, look for four in a row — and never recoverable for chess, because working
-- out that a position is checkmate needs the rules, and the rules live in a Deno library rather
-- than in Postgres.
--
-- That was survivable while the only place a result appeared was the screen you had just finished
-- on, which still had the board in front of it. It stops being survivable the moment anything asks
-- "how many have we each won" — a running record cannot be built from a fact nobody wrote down.
--
-- So the outcome is stored when it happens, by whoever knows it: `play_connect_four_move` below,
-- and `play-chess-move` in its own deploy.
--
-- Nullable, and null means two different things that are worth being able to tell apart: a game
-- still in play, and a game that ended without being played out — abandoned by a player or expired
-- after a fortnight. `status` already distinguishes those, so this column does not need to.

alter table public.game_sessions
  add column if not exists winner_id uuid references public.profiles(id),
  add column if not exists outcome text
  check (outcome is null or outcome in (
    'win', 'draw',
    -- The chess draws, kept apart rather than collapsed. "The same position three times over" and
    -- "neither of you has enough left to mate" are different games to have played, and a screen
    -- that wants to say which can only do so if this column remembers.
    'stalemate', 'insufficient_material', 'repetition', 'fifty_moves'
  ));

comment on column public.game_sessions.winner_id is
  'Who won, for games that have a winner. Null for a draw, and null for a game that never finished '
  '— `status` says which.';

comment on column public.game_sessions.outcome is
  'How a game ended. "win" with a winner_id, or one of the draw kinds. Written by the move RPC or '
  'edge function that ended it, because for chess it cannot be recomputed from the log in SQL.';

-- Same signature, so `create or replace` is allowed; the only change is that the move which ends
-- the game now says how.
create or replace function public.play_connect_four_move(p_session_id uuid, p_column int)
returns table (move_number int, finished boolean, winner_id uuid, is_draw boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_session public.game_sessions;
  v_played int;
  v_expected uuid;
  v_board int[];
  v_free int := 0;
  v_winner int;
  v_winner_id uuid;
  v_draw boolean := false;
  v_number int;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  if p_column < 0 or p_column > 6 then
    raise exception 'Column must be between 0 and 6';
  end if;

  select * into v_session from public.game_sessions where id = p_session_id;
  if not found or v_session.game_type <> 'connect_four' then
    raise exception 'No such game';
  end if;

  if v_session.couple_id is null or not public.is_couple_member(v_session.couple_id) then
    raise exception 'Not your game' using errcode = '42501';
  end if;

  if v_session.status not in ('active', 'waiting_for_partner') then
    raise exception 'connect_four_finished' using errcode = 'P0001';
  end if;

  select count(*) into v_played from public.game_moves where session_id = p_session_id;

  if v_played % 2 = 0 then
    v_expected := v_session.initiator_id;
  else
    select case when c.partner_a_id = v_session.initiator_id then c.partner_b_id else c.partner_a_id end
    into v_expected
    from public.couples c where c.id = v_session.couple_id;
  end if;

  if v_expected is distinct from v_me then
    raise exception 'connect_four_not_your_turn' using errcode = 'P0001';
  end if;

  v_board := private.connect_four_board(p_session_id);
  if v_board[0 * 7 + p_column + 1] <> 0 then
    raise exception 'connect_four_column_full' using errcode = 'P0001';
  end if;

  insert into public.game_moves (session_id, move_number, player_id, move)
  values (p_session_id, v_played, v_me, p_column::text)
  returning public.game_moves.move_number into v_number;

  v_board := private.connect_four_board(p_session_id);
  v_winner := private.connect_four_winner(v_board);

  if v_winner <> 0 then
    v_winner_id := v_me;  -- whoever just moved is the only player who can have won
  else
    select count(*) into v_free from unnest(v_board) as cell where cell = 0;
    v_draw := v_free = 0;
  end if;

  if v_winner <> 0 or v_draw then
    update public.game_sessions
    set status = 'completed',
        completed_at = now(),
        updated_at = now(),
        -- Written here rather than left to be recomputed. It is recoverable for this game and not
        -- for chess, and one way of recording a result is better than two.
        winner_id = v_winner_id,
        outcome = case when v_winner <> 0 then 'win' else 'draw' end
    where id = p_session_id;
  end if;

  return query select v_number, (v_winner <> 0 or v_draw), v_winner_id, v_draw;
end;
$$;

revoke all on function public.play_connect_four_move(uuid, int) from public, anon;
grant execute on function public.play_connect_four_move(uuid, int) to authenticated;
