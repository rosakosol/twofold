-- ---------------------------------------------------------------------------
-- Starting a sudoku
-- ---------------------------------------------------------------------------
--
-- A sudoku has no content bank. The other games draw a round from a table of prompts; this one is
-- generated on each device from the round's identity, so what the server has to decide is not
-- *which* puzzle but simply that there is one, and hand back an id both partners can derive it from.
--
-- Which is why `game_session_rounds.content_id` carries a fresh uuid rather than pointing at
-- anything. That column has no foreign key — every existing game type resolves it against whichever
-- prompt table matches — and 128 bits of identity is exactly what `SudokuGenerator` needs. No
-- content table, no seed column, no new shape.
--
-- ---------------------------------------------------------------------------
-- One puzzle, two people, played apart
-- ---------------------------------------------------------------------------
--
-- The session belongs to the couple and holds one round. Both partners open it, derive the same
-- grid, and solve it independently; their solves are two `game_responses` rows against the same
-- round, which is the shape the comparison screen will read. A solo player gets the same thing with
-- `couple_id` null — unpaired people already play this way, and a partner only adds the comparison.
--
-- Difficulty is not a deck. Decks exist to select content from a bank, and there is no bank here, so
-- the tier check is on the difficulty itself rather than on a `game_decks` row that would exist only
-- to carry it.

create or replace function public.start_sudoku_session(p_difficulty text)
returns table (session_id uuid, puzzle_id uuid, difficulty text, resumed boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_couple_id uuid;
  v_tier text;
  v_session public.game_sessions;
  v_round public.game_session_rounds;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  if p_difficulty not in ('easy', 'medium', 'hard', 'expert') then
    raise exception 'Unknown difficulty';
  end if;

  select id into v_couple_id
  from public.couples
  where status = 'active' and (partner_a_id = v_me or partner_b_id = v_me);

  -- Premium buys the hard half. Read through `couple_effective_tier` for a couple, so one
  -- subscription covers both of them, and from the profile for someone playing alone.
  --
  -- The solo branch checks `subscription_active`, not just `subscription_tier`. That column is
  -- deliberately never cleared when a subscription lapses (see 20260912000000, which closed this
  -- same hole in `get_daily_question_session`), so reading the tier bare hands Expert to someone
  -- whose premium ended months ago. This is the one shape of tier check in this codebase that has
  -- already been got wrong once.
  if p_difficulty in ('hard', 'expert') then
    v_tier := case
      when v_couple_id is not null then private.couple_effective_tier(v_couple_id)
      else coalesce(
        (select case when subscription_active then subscription_tier end
         from public.profiles where id = v_me),
        'plus'
      )
    end;
    if v_tier is distinct from 'premium' then
      raise exception 'This difficulty requires Premium';
    end if;
  end if;

  -- Resume rather than start again. Someone reopening a puzzle they are halfway through expects
  -- their grid, not a new one — and starting a second session for the same difficulty would leave
  -- the first stranded with a solve nobody can get back to.
  --
  -- Matched on difficulty as well as couple: playing an Easy while a Hard is unfinished is a
  -- reasonable thing to do, and neither should displace the other.
  select * into v_session
  from public.game_sessions gs
  where gs.game_type = 'sudoku'
    and gs.status in ('active', 'waiting_for_partner')
    and (
      (v_couple_id is not null and gs.couple_id = v_couple_id)
      or (v_couple_id is null and gs.couple_id is null and gs.initiator_id = v_me)
    )
    and exists (
      select 1 from public.game_session_rounds r
      where r.session_id = gs.id and r.discussion_status = p_difficulty
    )
  order by gs.created_at desc
  limit 1;

  if found then
    -- Aliased, and every column qualified through it. `returns table (session_id ...)` puts an
    -- output parameter of that name in scope for the whole body, so a bare `session_id` here is
    -- ambiguous against the column — Postgres refuses the statement outright rather than picking
    -- one, which at least makes it a startup error instead of a silent mismatch.
    select r.* into v_round from public.game_session_rounds r where r.session_id = v_session.id limit 1;
    return query select v_session.id, v_round.content_id, p_difficulty, true;
    return;
  end if;

  insert into public.game_sessions
    (couple_id, game_type, initiator_id, status, total_rounds, is_daily, started_at)
  values (v_couple_id, 'sudoku', v_me, 'active', 1, false, now())
  returning * into v_session;

  -- The puzzle's identity. Both partners read this same uuid and generate the same grid from it;
  -- nothing about the puzzle itself is ever stored or sent.
  --
  -- `discussion_status` carries the difficulty. It is a free-text column the conversation games use
  -- for their own purposes and nothing reads it for sudoku, so it holds the one fact a round needs
  -- that the session does not already have — rather than adding a column used by one game type.
  insert into public.game_session_rounds (session_id, round_number, content_id, discussion_status)
  values (v_session.id, 1, gen_random_uuid(), p_difficulty)
  returning * into v_round;

  return query select v_session.id, v_round.content_id, p_difficulty, false;
end;
$$;

revoke all on function public.start_sudoku_session(text) from public;
grant execute on function public.start_sudoku_session(text) to authenticated;
