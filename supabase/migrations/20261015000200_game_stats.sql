-- ---------------------------------------------------------------------------
-- The running record, for the four games that did not have one
-- ---------------------------------------------------------------------------
--
-- Sudoku already shows head-to-head and best times, aggregated on the device from solves it has
-- fetched. That works because a sudoku result is one number sitting in `game_responses.answer`.
--
-- It does not generalise. Connect 4 and chess keep their results nowhere the client can cheaply
-- reach — a board's outcome lives in `game_sessions.outcome`, and reconstructing it from the move
-- log would mean fetching every move of every game ever played to draw one line of text. So this
-- is a query rather than a download.
--
-- ---------------------------------------------------------------------------
-- One shape for four different games
-- ---------------------------------------------------------------------------
--
-- Every row is: a game, optionally a variant of it, how many each of them finished, how the
-- head-to-head stands, and each player's best. What "best" means differs and the column is
-- deliberately untyped about it — seconds for a word search, guesses for a word guess — because
-- the screen showing it always knows which game it asked about, and a column per unit would be
-- three columns that are null in every row but one.
--
-- Lower is better in both cases, which is what lets `my_best` be a single `numeric` rather than a
-- direction as well as a value.
--
-- ---------------------------------------------------------------------------
-- Who won
-- ---------------------------------------------------------------------------
--
-- Only sessions *both* of them finished count towards the head-to-head. A word that one of them
-- solved and the other never opened is not a win over anybody, and counting it would let somebody
-- lead a record their partner has not played.

create or replace function public.get_game_stats()
returns table (
  game_type text,
  variant text,
  my_finished int,
  partner_finished int,
  my_wins int,
  partner_wins int,
  draws int,
  my_best numeric,
  partner_best numeric
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_couple_id uuid;
  v_partner uuid;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select c.id,
         case when c.partner_a_id = v_me then c.partner_b_id else c.partner_a_id end
  into v_couple_id, v_partner
  from public.couples c
  where c.status = 'active' and (c.partner_a_id = v_me or c.partner_b_id = v_me);

  return query
  -- ---------------------------------------------------------------------------
  -- The two board games: the result is on the session, so this is a count
  -- ---------------------------------------------------------------------------
  with boards as (
    select
      gs.game_type::text as game_type,
      gs.winner_id,
      gs.outcome
    from public.game_sessions gs
    where gs.game_type in ('connect_four', 'chess')
      and gs.status = 'completed'
      and gs.outcome is not null
      and v_couple_id is not null
      and gs.couple_id = v_couple_id
  ),
  board_rows as (
    select
      b.game_type,
      null::text as variant,
      count(*) filter (where b.winner_id = v_me)::int as my_wins,
      count(*) filter (where b.winner_id = v_partner)::int as partner_wins,
      count(*) filter (where b.winner_id is null)::int as draws
    from boards b
    group by b.game_type
  ),

  -- ---------------------------------------------------------------------------
  -- The two puzzle games: the result is inside the response payload
  -- ---------------------------------------------------------------------------
  --
  -- Parsed here rather than on the device, because the alternative is downloading every response
  -- either of them has ever written to count them. The formats are pinned by the Swift tests that
  -- own them (`WordGuessPlayStateTests`, `WordSearchPlayStateTests`); a payload this cannot read
  -- is skipped rather than guessed at.
  responses as (
    select
      gs.id as session_id,
      gs.game_type::text as game_type,
      r.theme as variant,
      gr.responder_id,
      split_part(gr.answer->>'value', '|', 1) as version,
      gr.answer->>'value' as payload
    from public.game_sessions gs
    join public.game_responses gr on gr.session_id = gs.id
    left join public.game_session_rounds r on r.session_id = gs.id and r.round_number = 1
    where gs.game_type in ('word_guess', 'word_search')
      and (
        (v_couple_id is not null and gs.couple_id = v_couple_id)
        or (v_couple_id is null and gs.couple_id is null and gs.initiator_id = v_me)
      )
      and gr.responder_id in (v_me, v_partner)
  ),
  scored as (
    select
      p.session_id,
      p.game_type,
      p.variant,
      p.responder_id,
      case
        -- "wordguess.v1|crane,toads|97|1" — the score is how many guesses it took, and a board
        -- that was never solved has no score at all rather than a score of six.
        when p.version = 'wordguess.v1' and split_part(p.payload, '|', 4) = '1'
          then array_length(string_to_array(split_part(p.payload, '|', 2), ','), 1)::numeric
        -- "wordsearch.v1|FLIGHT,GATE|143|1" — the score is the time, and only a cleared grid has
        -- one.
        when p.version = 'wordsearch.v1' and split_part(p.payload, '|', 4) = '1'
          then nullif(split_part(p.payload, '|', 3), '')::numeric
        else null
      end as score
    from responses p
    where p.version in ('wordguess.v1', 'wordsearch.v1')
  ),
  -- Both sides of a session, side by side, so a head-to-head can be decided. A session only one of
  -- them finished produces no row here and so counts towards nobody.
  duels as (
    select
      s.game_type,
      s.variant,
      max(s.score) filter (where s.responder_id = v_me) as mine,
      max(s.score) filter (where s.responder_id = v_partner) as theirs
    from scored s
    group by s.session_id, s.game_type, s.variant
    having count(*) filter (where s.responder_id = v_me) > 0
       and count(*) filter (where s.responder_id = v_partner) > 0
  ),
  puzzle_rows as (
    select
      d.game_type,
      d.variant,
      -- Lower is better for both games: fewer guesses, and less time.
      count(*) filter (where d.mine is not null and (d.theirs is null or d.mine < d.theirs))::int as my_wins,
      count(*) filter (where d.theirs is not null and (d.mine is null or d.theirs < d.mine))::int as partner_wins,
      count(*) filter (where d.mine is not null and d.theirs is not null and d.mine = d.theirs)::int as draws
    from duels d
    group by d.game_type, d.variant
  ),
  puzzle_totals as (
    select
      s.game_type,
      s.variant,
      count(*) filter (where s.responder_id = v_me and s.score is not null)::int as my_finished,
      count(*) filter (where s.responder_id = v_partner and s.score is not null)::int as partner_finished,
      min(s.score) filter (where s.responder_id = v_me) as my_best,
      min(s.score) filter (where s.responder_id = v_partner) as partner_best
    from scored s
    group by s.game_type, s.variant
  )

  select
    t.game_type,
    t.variant,
    t.my_finished,
    t.partner_finished,
    coalesce(w.my_wins, 0),
    coalesce(w.partner_wins, 0),
    coalesce(w.draws, 0),
    t.my_best,
    t.partner_best
  from puzzle_totals t
  left join puzzle_rows w
    on w.game_type = t.game_type and w.variant is not distinct from t.variant

  union all

  select
    b.game_type,
    b.variant,
    -- A board game has no "finished" count separate from its results: every completed game was
    -- played by both of them, so the total is simply the three outcomes added up.
    (b.my_wins + b.partner_wins + b.draws),
    (b.my_wins + b.partner_wins + b.draws),
    b.my_wins,
    b.partner_wins,
    b.draws,
    null::numeric,
    null::numeric
  from board_rows b;
end;
$$;

revoke all on function public.get_game_stats() from public, anon;
grant execute on function public.get_game_stats() to authenticated;

comment on function public.get_game_stats() is
  'Head-to-head and bests for word_guess, word_search, connect_four and chess. Sudoku is absent '
  'deliberately: it aggregates its own on the device from solves it has already fetched, and two '
  'implementations of one record is one too many.';
