-- ---------------------------------------------------------------------------
-- Playing Connect 4
-- ---------------------------------------------------------------------------
--
-- Starting a game is the familiar shape: one session, one round, no content. What is new is that
-- the session now has a *position*, and this file is where it lives.
--
-- ---------------------------------------------------------------------------
-- Why the server decides who won
-- ---------------------------------------------------------------------------
--
-- The games plan settled that move validation stays on the device: both clients apply the same
-- rules, a disagreement surfaces immediately, and the real risk is a bug rather than cheating.
-- That reasoning holds for "is this a legal move". It does not hold for "is the game over", for
-- two reasons:
--
--   * Ending the game is a write. Somebody has to set `status = 'completed'`, and if that is a
--     client saying "I won", then a bug in one device's win detection ends a game that is still
--     being played — for both of them, with no way back, because the moves are append-only.
--   * The server already has every move. Replaying 42 of them and looking for four in a row is
--     cheap and total. There is no reason to be told something that can be known.
--
-- So `play_connect_four_move` drops the disc, then works out for itself whether that ended the
-- game. The client still detects the win too — it has to, to draw the board — but nothing depends
-- on it being right.
--
-- Chess will not be able to do this, and should not pretend to: legal move generation is the hard
-- part there and a Swift library will be doing it. That is a decision for that game, made on its
-- own terms, and the fact that it goes the other way is exactly why this one is written down.
--
-- ---------------------------------------------------------------------------
-- Board layout
-- ---------------------------------------------------------------------------
--
-- Seven columns, six rows, kept as a 42-element array. Index is `row * 7 + column + 1` — Postgres
-- arrays are 1-based — with row 0 at the top, so gravity means a disc falls to the *largest* empty
-- row in its column. 0 is empty, 1 is the player who moved first, 2 is the other.
--
-- The player who moved first is the session's initiator. That is the only ordering the two devices
-- can both derive without being told.

create or replace function private.connect_four_board(p_session_id uuid)
returns int[]
language plpgsql
stable
set search_path = public
as $$
declare
  v_board int[] := array_fill(0, array[42]);
  v_initiator uuid;
  v_move record;
  v_column int;
  v_row int;
  v_piece int;
begin
  select initiator_id into v_initiator from public.game_sessions where id = p_session_id;

  for v_move in
    select m.move, m.player_id from public.game_moves m
    where m.session_id = p_session_id
    order by m.move_number
  loop
    v_column := v_move.move::int;
    v_piece := case when v_move.player_id = v_initiator then 1 else 2 end;

    -- Gravity: the lowest empty cell in the column, searched from the bottom row up.
    v_row := null;
    for r in reverse 5..0 loop
      if v_board[r * 7 + v_column + 1] = 0 then
        v_row := r;
        exit;
      end if;
    end loop;

    -- A full column cannot happen — `play_connect_four_move` refuses one before inserting — but
    -- replaying a log must never throw, or one bad row would make the whole game unreadable.
    if v_row is not null then
      v_board[v_row * 7 + v_column + 1] := v_piece;
    end if;
  end loop;

  return v_board;
end;
$$;

-- 1 or 2 if that player has four in a row, 0 for nobody. Checked in four directions from every
-- cell: right, down, down-right, down-left. The other four are the same lines walked backwards.
create or replace function private.connect_four_winner(p_board int[])
returns int
language plpgsql
immutable
as $$
declare
  v_piece int;
  v_directions int[][] := array[array[0, 1], array[1, 0], array[1, 1], array[1, -1]];
  v_row_step int;
  v_column_step int;
  v_run int;
  v_r int;
  v_c int;
begin
  for row0 in 0..5 loop
    for col0 in 0..6 loop
      v_piece := p_board[row0 * 7 + col0 + 1];
      continue when v_piece = 0;

      for d in 1..4 loop
        v_row_step := v_directions[d][1];
        v_column_step := v_directions[d][2];
        v_run := 1;
        v_r := row0;
        v_c := col0;

        while v_run < 4 loop
          v_r := v_r + v_row_step;
          v_c := v_c + v_column_step;
          exit when v_r < 0 or v_r > 5 or v_c < 0 or v_c > 6;
          exit when p_board[v_r * 7 + v_c + 1] <> v_piece;
          v_run := v_run + 1;
        end loop;

        if v_run >= 4 then
          return v_piece;
        end if;
      end loop;
    end loop;
  end loop;

  return 0;
end;
$$;

-- ---------------------------------------------------------------------------
-- Starting one
-- ---------------------------------------------------------------------------
--
-- Free on every plan. Connect 4 has no content to gate and no difficulty to sell — the plan settled
-- that its tiering would be a game-level flag if it had one, and it does not.
--
-- Requires a partner, and says so rather than starting a game nobody can answer. This is the first
-- game here that genuinely cannot be played alone: the other four all have a solo path because a
-- puzzle is still a puzzle by yourself, and a board with one player is not a game.
create or replace function public.start_connect_four_session()
returns table (session_id uuid, resumed boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_couple_id uuid;
  v_session public.game_sessions;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select id into v_couple_id
  from public.couples
  where status = 'active' and (partner_a_id = v_me or partner_b_id = v_me);

  if v_couple_id is null then
    raise exception 'connect_four_needs_partner' using errcode = 'P0001';
  end if;

  -- One game at a time per couple. A second board started while the first is unfinished would
  -- leave the first stranded mid-game, and "whose turn is it" becomes a question about which board.
  select * into v_session
  from public.game_sessions gs
  where gs.game_type = 'connect_four'
    and gs.couple_id = v_couple_id
    and gs.status in ('active', 'waiting_for_partner')
  order by gs.created_at desc
  limit 1;

  if found then
    return query select v_session.id, true;
    return;
  end if;

  insert into public.game_sessions
    (couple_id, game_type, initiator_id, status, total_rounds, is_daily, started_at)
  values (v_couple_id, 'connect_four', v_me, 'active', 1, false, now())
  returning * into v_session;

  -- A round, so the session has the same shape as every other one and `fetchGameSession` has
  -- something to return. Its `content_id` is unused: a Connect 4 board is not generated from an
  -- identity, it is built from the moves.
  insert into public.game_session_rounds (session_id, round_number, content_id)
  values (v_session.id, 1, gen_random_uuid());

  return query select v_session.id, false;
end;
$$;

-- ---------------------------------------------------------------------------
-- Dropping a disc
-- ---------------------------------------------------------------------------
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

  -- Any status that is not a live game, not just 'completed'. A board can also be `abandoned` (a
  -- player ended it) or `archived` (it expired — see 20261013000300), and both of those are just
  -- as over. Checking only for 'completed' would have let a disc land on a game that had been
  -- closed weeks earlier, reopening it for one player and not the other.
  if v_session.status not in ('active', 'waiting_for_partner') then
    raise exception 'connect_four_finished' using errcode = 'P0001';
  end if;

  select count(*) into v_played from public.game_moves where session_id = p_session_id;

  -- The initiator moves first, and they alternate from there. Derived from the move count rather
  -- than stored, so there is no "current player" column that can disagree with the log.
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
  -- Full column: the top cell of it is taken.
  if v_board[0 * 7 + p_column + 1] <> 0 then
    raise exception 'connect_four_column_full' using errcode = 'P0001';
  end if;

  insert into public.game_moves (session_id, move_number, player_id, move)
  values (p_session_id, v_played, v_me, p_column::text)
  returning public.game_moves.move_number into v_number;

  -- Re-derive rather than patch the array above: one way of building a board, used by the check
  -- that ends the game and by the check that refused a full column, is one fewer way for those two
  -- to disagree about what is on it.
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
    set status = 'completed', completed_at = now(), updated_at = now()
    where id = p_session_id;
  end if;

  return query select v_number, (v_winner <> 0 or v_draw), v_winner_id, v_draw;
end;
$$;

revoke all on function public.start_connect_four_session() from public, anon;
grant execute on function public.start_connect_four_session() to authenticated;
revoke all on function public.play_connect_four_move(uuid, int) from public, anon;
grant execute on function public.play_connect_four_move(uuid, int) to authenticated;
