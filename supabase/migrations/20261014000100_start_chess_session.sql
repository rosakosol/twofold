-- ---------------------------------------------------------------------------
-- Starting a chess game
-- ---------------------------------------------------------------------------
--
-- The same shape as `start_connect_four_session`: one board per couple, resumed rather than
-- restarted, requires a partner, and the initiator moves first — which for chess means the
-- initiator plays white.
--
-- Premium, unlike Connect 4. That is what the games plan settled, and it is the only one of the
-- five whose tiering is a game-level flag rather than a property of its content: there is no deck
-- to gate, no difficulty to sell and no allowance to ration.
--
-- ---------------------------------------------------------------------------
-- Where the moves are validated, and why it is not here
-- ---------------------------------------------------------------------------
--
-- Connect 4 validates in `play_connect_four_move`, in plpgsql, because replaying 42 discs and
-- looking for four in a row is forty lines. Chess is not that. Legal move generation — castling
-- through check, en passant exposing a pin, the difference between checkmate and stalemate — is a
-- library's worth of work, and plpgsql is the wrong language to write it in twice.
--
-- The conclusion is *not* that the client must decide. That was the wrong reading, and it confused
-- "the server" with "the database". Moves go to the `play-chess-move` edge function, which replays
-- the log with `chess.js` and decides for itself whether the move is legal and whether it ended the
-- game. The principle is the same one Connect 4 settled: ending a game is a write, the log is
-- append-only, and a bug in one device's rules must not be able to end a game wrongly for both
-- people. Only the mechanism differs — Deno rather than Postgres.
--
-- So there is no `play_chess_move` RPC. `game_moves` grants no insert to `authenticated` at all,
-- and the edge function writes with the service role, which is what makes the edge function the
-- only way a move can reach the table.

create or replace function public.start_chess_session()
returns table (session_id uuid, resumed boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_couple_id uuid;
  v_tier text;
  v_session public.game_sessions;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select id into v_couple_id
  from public.couples
  where status = 'active' and (partner_a_id = v_me or partner_b_id = v_me);

  if v_couple_id is null then
    raise exception 'chess_needs_partner' using errcode = 'P0001';
  end if;

  -- Read through `couple_effective_tier`, so one subscription covers both of them — including the
  -- partner who did not buy it, who would otherwise be locked out of a board they are meant to be
  -- sharing.
  v_tier := private.couple_effective_tier(v_couple_id);
  if v_tier is distinct from 'premium' then
    raise exception 'chess_requires_premium' using errcode = 'P0001';
  end if;

  -- Close anything this couple has plainly finished with before looking for a game to resume, so a
  -- board abandoned months ago cannot be handed back as theirs. Same call the nightly cron makes.
  perform private.expire_stale_move_games(p_couple_id => v_couple_id);

  select * into v_session
  from public.game_sessions gs
  where gs.game_type = 'chess'
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
  values (v_couple_id, 'chess', v_me, 'active', 1, false, now())
  returning * into v_session;

  -- A round, so the session has the same shape as every other one. Its `content_id` is unused: a
  -- chess game is not generated from an identity, it is built from the moves.
  insert into public.game_session_rounds (session_id, round_number, content_id)
  values (v_session.id, 1, gen_random_uuid());

  return query select v_session.id, false;
end;
$$;

revoke all on function public.start_chess_session() from public, anon;
grant execute on function public.start_chess_session() to authenticated;

-- ---------------------------------------------------------------------------
-- Expiry covers chess too
-- ---------------------------------------------------------------------------
--
-- Same fortnight, same reasoning, and more pressing here than for Connect 4: a chess game runs
-- longer, so it has more chances to be forgotten, and one board per couple means a forgotten one
-- blocks the next.
--
-- The game types are listed rather than "every turn-based game" because there is no column that
-- says which those are. A sixth game that keeps a `game_moves` log must be added here, and the test
-- asserting a 90-day-old sudoku is untouched is what keeps that from being done by widening this to
-- everything.
create or replace function private.expire_stale_move_games(
  p_couple_id uuid default null,
  p_after interval default '14 days'
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_expired int;
begin
  with stale as (
    select gs.id
    from public.game_sessions gs
    where gs.game_type in ('connect_four', 'chess')
      and gs.status in ('active', 'waiting_for_partner')
      and (p_couple_id is null or gs.couple_id = p_couple_id)
      -- The later of "when the last move landed" and "when the board was created", so an untouched
      -- board expires on its own age and a played one expires on its silence.
      and coalesce(
        (select max(m.created_at) from public.game_moves m where m.session_id = gs.id),
        gs.created_at
      ) < now() - p_after
  )
  update public.game_sessions gs
  set status = 'archived', updated_at = now()
  from stale
  where gs.id = stale.id;

  get diagnostics v_expired = row_count;
  return v_expired;
end;
$$;

revoke all on function private.expire_stale_move_games(uuid, interval) from public, anon, authenticated;

comment on function private.expire_stale_move_games(uuid, interval) is
  'Closes Connect 4 and chess boards neither partner has touched in p_after. Called nightly by cron '
  'for everybody, and by the start RPCs for the one couple about to play — so a stale board cannot '
  'block a new game even if the cron is not running.';
