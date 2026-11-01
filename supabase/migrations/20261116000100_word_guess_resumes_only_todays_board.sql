-- Word Guess no longer hands a couple yesterday's finished board for ever (GAME-4).
--
-- `start_word_guess_session` resumed a couple's latest open board whatever day it was from. Take a
-- partner who finished while the other never played: "Play today's word" reopened that finished
-- board on every day after, Premium included, and the archive cron rescued them only when the one
-- who never played was not the one who started it.
--
-- Now a couple resumes a board only when it is from today, or the caller has not finished it. An
-- older board the caller has finished stays open for the partner, and the caller falls through to
-- the allowance and today's board. Unchanged from 20261011000100 otherwise, including the solo
-- branch and the allowance.

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
  --
  -- For a couple, only a board from today or one the caller has not finished. Without that, a
  -- partner who finished while the other never played was handed the same finished board every
  -- day after, and nothing ended it if the one who never played had started it (GAME-4). An older
  -- board the caller has finished stays open for the partner, who still reaches it here, and the
  -- caller falls through to today's.
  select * into v_session
  from public.game_sessions gs
  where gs.game_type = 'word_guess'
    and gs.status in ('active', 'waiting_for_partner')
    and (
      (v_couple_id is not null and gs.couple_id = v_couple_id
        and (
          gs.daily_local_date = v_local_date
          or not exists (
            select 1 from public.game_responses r
            where r.session_id = gs.id and r.responder_id = v_me
          )
        ))
      or (v_couple_id is null and gs.couple_id is null and gs.initiator_id = v_me)
    )
  order by gs.created_at desc
  limit 1;

  if found then
    select exists (
      select 1 from public.game_responses r
      where r.session_id = v_session.id and r.responder_id = v_me
    ) into v_i_have_answered;

    -- Solo, a board the player has answered is finished (`advance_game_session` completes a solo
    -- session on its one response, so this is a guard rather than the common case) and is never
    -- handed back. Paired, a finished board from today that is still waiting on the partner is
    -- exactly what should be resumed: it is where the comparison will appear.
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
