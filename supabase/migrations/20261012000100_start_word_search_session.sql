-- ---------------------------------------------------------------------------
-- Starting a Word Search
-- ---------------------------------------------------------------------------
--
-- The same shape as `start_sudoku_session`, with themes where that one has difficulties: no content
-- bank, no seed column, the round's `content_id` carrying a fresh uuid that each device turns into
-- the same grid (`WordSearchGenerator.puzzle(for:theme:)`).
--
-- The theme gets its own column, for the reason 20261010000200 gives at length. Sudoku first put
-- its difficulty in `game_session_rounds.discussion_status` on the grounds that it is a free-text
-- column nothing reads for a generated game — true of the database and false of the app, which
-- decodes that column into a closed two-case enum. A round holding 'travel' would not decode, and
-- `fetchGameSession` would throw for the whole session: every word search would open, be played,
-- and then fail to load, taking any game-history screen that touched one with it.
--
-- That mistake is why this file does not repeat it. The check constraint also keeps the six themes
-- in one place rather than spread across the RPC and the client.

--
-- ---------------------------------------------------------------------------
-- What the tier buys
-- ---------------------------------------------------------------------------
--
-- Travel and Love are on every plan; the other four themes are Premium. Unlike Word Guess there is
-- no daily allowance — a word search has no failure state and no limit that *is* the game, so
-- rationing it would be a wall in front of a puzzle rather than a rule of one.
--
-- The check is on the theme itself rather than on a `game_decks` row, for the reason sudoku's is:
-- decks exist to select content from a bank, and there is no bank here.
--
-- The solo branch checks `subscription_active`, not just `subscription_tier`. That column is
-- deliberately never cleared when a subscription lapses, so reading the tier bare hands the premium
-- themes to someone whose Premium ended months ago. This is the one shape of tier check in this
-- codebase that has already been got wrong once — see 20260912000000.

alter table public.game_session_rounds
  add column if not exists theme text
  check (theme is null or theme in ('travel', 'love', 'food', 'nature', 'cities', 'music'));

create or replace function public.start_word_search_session(p_theme text)
returns table (session_id uuid, puzzle_id uuid, theme text, resumed boolean)
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
  v_i_have_answered boolean;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  if p_theme not in ('travel', 'love', 'food', 'nature', 'cities', 'music') then
    raise exception 'Unknown theme';
  end if;

  select id into v_couple_id
  from public.couples
  where status = 'active' and (partner_a_id = v_me or partner_b_id = v_me);

  if p_theme in ('food', 'nature', 'cities', 'music') then
    v_tier := case
      when v_couple_id is not null then private.couple_effective_tier(v_couple_id)
      else coalesce(
        (select case when subscription_active then subscription_tier end
         from public.profiles where id = v_me),
        'plus'
      )
    end;
    if v_tier is distinct from 'premium' then
      raise exception 'This theme requires Premium';
    end if;
  end if;

  -- Resume rather than start again. Someone reopening a grid they are partway through expects
  -- their grid, and starting a second session for the same theme would strand the first with
  -- words found that nobody can get back to.
  --
  -- Matched on theme as well as couple: hunting Travel while a Cities grid sits unfinished is a
  -- reasonable thing to do, and neither should displace the other.
  select * into v_session
  from public.game_sessions gs
  where gs.game_type = 'word_search'
    and gs.status in ('active', 'waiting_for_partner')
    and (
      (v_couple_id is not null and gs.couple_id = v_couple_id)
      or (v_couple_id is null and gs.couple_id is null and gs.initiator_id = v_me)
    )
    and exists (
      select 1 from public.game_session_rounds r
      where r.session_id = gs.id and r.theme = p_theme
    )
  order by gs.created_at desc
  limit 1;

  if found then
    select exists (
      select 1 from public.game_responses r
      where r.session_id = v_session.id and r.responder_id = v_me
    ) into v_i_have_answered;

    -- A solo session never reaches `completed` — `advance_game_session` waits for a second
    -- responder who is never coming — so without this branch an unpaired player would be handed
    -- their one finished grid back forever and could never play that theme again. Paired, a
    -- finished grid still waiting on the partner is exactly what should be resumed: it is where
    -- the comparison will appear.
    if v_couple_id is not null or not v_i_have_answered then
      -- Aliased, and every column qualified through it. `returns table (session_id ...)` puts an
      -- output parameter of that name in scope for the whole body, so a bare `session_id` here is
      -- ambiguous against the column and Postgres refuses the statement outright.
      select r.* into v_round
      from public.game_session_rounds r where r.session_id = v_session.id limit 1;
      return query select v_session.id, v_round.content_id, p_theme, true;
      return;
    end if;
  end if;

  insert into public.game_sessions
    (couple_id, game_type, initiator_id, status, total_rounds, is_daily, started_at)
  values (v_couple_id, 'word_search', v_me, 'active', 1, false, now())
  returning * into v_session;

  -- The grid's identity. Both partners read this uuid and generate the same letters from it;
  -- nothing about the grid itself is ever stored or sent.
  insert into public.game_session_rounds (session_id, round_number, content_id, theme)
  values (v_session.id, 1, gen_random_uuid(), p_theme)
  returning * into v_round;

  return query select v_session.id, v_round.content_id, p_theme, false;
end;
$$;

revoke all on function public.start_word_search_session(text) from public, anon;
grant execute on function public.start_word_search_session(text) to authenticated;
