-- ---------------------------------------------------------------------------
-- A board nobody came back to
-- ---------------------------------------------------------------------------
--
-- Connect 4 is the first game here that can be left half-played. Every other one is a puzzle you
-- finish or abandon in a sitting; this is a position that waits for somebody, and if that somebody
-- never returns it waits forever.
--
-- That is worse than untidy, because `start_connect_four_session` allows one board per couple. A
-- game forgotten in March is a game they cannot start in April — the resume branch keeps handing
-- back the same abandoned position, and nothing about the screen explains why there is no new one.
--
-- ---------------------------------------------------------------------------
-- Fourteen days
-- ---------------------------------------------------------------------------
--
-- Long, deliberately. This game has no clock and is meant to be played a move at a time whenever
-- each of them gets to it — that is the pitch on its own entry screen. A week would close games
-- that are merely slow, and "slow" is the normal case for a couple in different timezones, one of
-- whom is on a plane. Fourteen days of neither of them touching it is not slow, it is over.
--
-- Measured from the last move rather than from when the game started, so a long game that is still
-- being played is never at risk however old it is. A board with no moves at all falls back to its
-- own creation time.
--
-- `archived`, not `abandoned`. The two words already mean different things here: `abandoned` is
-- what `abandon_game_session` writes when a person puts a game down, and `archived` is what the
-- system writes when it closes one on their behalf. Keeping them apart is what lets a future
-- screen say "you left this" or "this expired" without guessing.

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
    where gs.game_type = 'connect_four'
      and gs.status in ('active', 'waiting_for_partner')
      and (p_couple_id is null or gs.couple_id = p_couple_id)
      -- The later of "when the last disc landed" and "when the board was created", so an untouched
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
  'Closes Connect 4 boards neither partner has touched in p_after. Called nightly by cron for '
  'everybody, and by start_connect_four_session for the one couple about to play — so a stale '
  'board cannot block a new game even if the cron is not running.';

-- Nightly, and pure SQL: there is nothing to notify and nobody to call, so this needs none of the
-- pg_net/Vault plumbing the jobs that hit an edge function do.
select cron.schedule(
  'expire-stale-move-games',
  '0 4 * * *',
  'select private.expire_stale_move_games();'
);

-- ---------------------------------------------------------------------------
-- And the same check where it actually matters
-- ---------------------------------------------------------------------------
--
-- The cron closes boards on time. This closes the one board standing between a couple and a new
-- game, at the moment they ask for it — so "I cannot start a game" is never a symptom of a
-- background job being down. Same signature, so `create or replace` is allowed; only the expiry
-- sweep is added.
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

  -- Before looking for a game to resume, close any this couple has plainly finished with. Without
  -- this the resume below would hand back a board from months ago and call it theirs.
  perform private.expire_stale_move_games(p_couple_id => v_couple_id);

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

revoke all on function public.start_connect_four_session() from public, anon;
grant execute on function public.start_connect_four_session() to authenticated;
