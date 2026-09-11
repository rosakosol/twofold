-- ---------------------------------------------------------------------------
-- Starting a Word Guess
-- ---------------------------------------------------------------------------
--
-- Same shape as `start_sudoku_session`: no content bank, no seed column. The round's `content_id`
-- carries a fresh uuid and each device derives the word from it (`WordGuessWords.answer(for:)`).
-- The word is never stored, and that is the point rather than an economy — both partners can read
-- the session row, so a column holding the answer is a column one of them can read the answer out
-- of.
--
-- ---------------------------------------------------------------------------
-- What the tier buys
-- ---------------------------------------------------------------------------
--
-- Plus gets one board a day; Premium gets as many as it wants. This is the one game whose limit is
-- the game — a word a day is the format, not a wall in front of it — so the Plus experience is the
-- whole thing rather than a trimmed version of it.
--
-- The day is the couple's shared local day (`private.viewer_day`), the same boundary the daily
-- question and the streak already use, so "tomorrow" means one thing across the app.
--
-- ---------------------------------------------------------------------------
-- This is not the Daily Question and must never become it
-- ---------------------------------------------------------------------------
--
-- `is_daily` stays false. That column drives the streak in `advance_game_session`, and the streak
-- is deliberately tied to the daily conversation question alone. A word game that fed it would
-- change what the streak means — a couple could hold a hundred-day streak having never once
-- answered a question about each other.
--
-- `daily_local_date` *is* set, which needs saying because the name suggests otherwise. It means
-- "the local day this session belongs to", and every existing reader of it already filters on
-- `is_daily` (the two indexes on it are partial `where is_daily`), so a word_guess row is invisible
-- to all of them. The allowance query below filters on `game_type` for the same reason in reverse.

comment on column public.game_sessions.daily_local_date is
  'The couple''s shared local day this session belongs to. Set for the Daily Question (where it '
  'also enforces one-per-day via partial unique indexes) and for word_guess (where it enforces the '
  'Plus allowance). Every reader must filter on the game it means, since the column is shared.';

create or replace function public.start_word_guess_session()
returns table (session_id uuid, puzzle_id uuid, resumed boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_couple_id uuid;
  v_local_date date;
  v_tier text;
  v_started_today int;
  v_session public.game_sessions;
  v_round public.game_session_rounds;
  v_i_have_answered boolean;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  -- Resolves the couple and the shared day in one call, and handles the unpaired case: solo players
  -- get their own local day and a null couple.
  select vd.couple_id, vd.local_date into v_couple_id, v_local_date
  from private.viewer_day() vd;

  if v_local_date is null then
    raise exception 'No profile for the current user';
  end if;

  -- ---------------------------------------------------------------------------
  -- Resume before starting
  -- ---------------------------------------------------------------------------
  --
  -- Someone reopening a board they are halfway through expects their board, and starting a second
  -- session would strand the first with guesses nobody can get back to.
  select * into v_session
  from public.game_sessions gs
  where gs.game_type = 'word_guess'
    and gs.status in ('active', 'waiting_for_partner')
    and (
      (v_couple_id is not null and gs.couple_id = v_couple_id)
      or (v_couple_id is null and gs.couple_id is null and gs.initiator_id = v_me)
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
    -- their one finished board back forever and could never play another. Paired, a finished board
    -- that is still waiting on the partner is exactly what should be resumed: it is where the
    -- comparison will appear.
    if v_couple_id is not null or not v_i_have_answered then
      select r.* into v_round
      from public.game_session_rounds r where r.session_id = v_session.id limit 1;
      return query select v_session.id, v_round.content_id, true;
      return;
    end if;
  end if;

  -- ---------------------------------------------------------------------------
  -- The allowance
  -- ---------------------------------------------------------------------------
  --
  -- Read through `couple_effective_tier` for a couple, so one subscription covers both of them, and
  -- from the profile for someone playing alone.
  --
  -- The solo branch checks `subscription_active`, not just `subscription_tier`: that column is
  -- deliberately never cleared when a subscription lapses, so reading the tier bare would hand
  -- unlimited boards to someone whose Premium ended months ago. This is the shape of tier check
  -- this codebase has already got wrong once — see 20260912000000 and `start_sudoku_session`.
  v_tier := case
    when v_couple_id is not null then private.couple_effective_tier(v_couple_id)
    else coalesce(
      (select case when subscription_active then subscription_tier end
       from public.profiles where id = v_me),
      'plus'
    )
  end;

  if v_tier is distinct from 'premium' then
    select count(*) into v_started_today
    from public.game_sessions gs
    where gs.game_type = 'word_guess'
      and gs.daily_local_date = v_local_date
      and (
        (v_couple_id is not null and gs.couple_id = v_couple_id)
        or (v_couple_id is null and gs.couple_id is null and gs.initiator_id = v_me)
      );

    -- Counted per couple, not per person, because the board is shared: one word a day means one
    -- word between the two of them, which is the thing they then compare.
    if v_started_today >= 1 then
      raise exception 'word_guess_daily_limit' using errcode = 'P0001';
    end if;
  end if;

  insert into public.game_sessions
    (couple_id, game_type, initiator_id, status, total_rounds, is_daily, daily_local_date, started_at)
  values (v_couple_id, 'word_guess', v_me, 'active', 1, false, v_local_date, now())
  returning * into v_session;

  -- The word's identity. Both partners read this uuid and derive the same word from it; the word
  -- itself is never stored or sent.
  insert into public.game_session_rounds (session_id, round_number, content_id)
  values (v_session.id, 1, gen_random_uuid())
  returning * into v_round;

  return query select v_session.id, v_round.content_id, false;
end;
$$;

revoke all on function public.start_word_guess_session() from public, anon;
grant execute on function public.start_word_guess_session() to authenticated;

-- Makes the allowance count an index lookup rather than a scan of every session the couple has
-- ever played. Partial, mirroring the two `where is_daily` indexes this column already carries.
create index if not exists game_sessions_word_guess_day_idx
  on public.game_sessions (couple_id, daily_local_date)
  where game_type = 'word_guess';

create index if not exists game_sessions_word_guess_solo_day_idx
  on public.game_sessions (initiator_id, daily_local_date)
  where game_type = 'word_guess' and couple_id is null;
