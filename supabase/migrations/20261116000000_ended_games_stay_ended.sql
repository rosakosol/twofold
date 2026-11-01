-- A game that has ended stays ended.
--
-- Three ways an ended session used to come back, or a finished one be thrown away:
--
--   * `advance_game_session` rewrote the session's status on every new response without looking
--     at what it was. The first late answer to an `abandoned` or `archived` session put it back to
--     `active` (a couple's) or `completed` (a solo one).
--   * The insert and update policies on `game_responses` let an answer into a session in any
--     status, so that late answer was always accepted. The way it happens in the app: one partner
--     abandons a shared puzzle while the other finishes it offline, and the result, sent on
--     reconnect, brings the puzzle back for both of them — out of Open Games and `start_*_session`
--     alike. The abandon did not stick (2-games-NEW-1).
--   * `abandon_game_session` had no status check, so any client could turn a finished result into
--     an abandonment — exactly what solo Sudoku's "Play another" used to do (GAME-1).
--
-- An answer to an ended session is now refused, with the same 42501 every other refusal here
-- gets, so the app can tell it from a dropped connection and stop retrying. `completed` is not an
-- ended state for this purpose: a result resent after its reply was lost is an upsert into a
-- completed session, and editing a finished deck's answers is a feature.

-- Restrictive, so these sit on top of the existing permissive policies rather than restating them.
drop policy if exists game_responses_session_not_ended_insert on public.game_responses;
create policy "game_responses_session_not_ended_insert" on public.game_responses
  as restrictive
  for insert with check (
    not exists (
      select 1 from public.game_sessions gs
      where gs.id = game_responses.session_id
        and gs.status in ('abandoned', 'archived')
    )
  );

-- The upsert's other half. A row already in an abandoned session (an answer given before it was
-- abandoned) must not be rewritten into it either.
drop policy if exists game_responses_session_not_ended_update on public.game_responses;
create policy "game_responses_session_not_ended_update" on public.game_responses
  as restrictive
  for update
  using (
    not exists (
      select 1 from public.game_sessions gs
      where gs.id = game_responses.session_id
        and gs.status in ('abandoned', 'archived')
    )
  )
  with check (
    not exists (
      select 1 from public.game_sessions gs
      where gs.id = game_responses.session_id
        and gs.status in ('abandoned', 'archived')
    )
  );

-- The trigger, unchanged from 20260912000100 except for reading the status and leaving an ended
-- session alone. The policies above are the front door; this is the trigger not reopening the
-- session whoever gets an answer in — a security definer function, or the service role.
create or replace function public.advance_game_session()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_total_rounds int;
  v_couple_id uuid;
  v_initiator_id uuid;
  v_status public.game_status;
  v_partner_a_id uuid;
  v_partner_b_id uuid;
  v_partner_a_count int;
  v_partner_b_count int;
  v_solo_count int;
  v_both_complete boolean;
  v_is_daily boolean;
  v_local_date date;
begin
  select total_rounds, couple_id, is_daily, initiator_id, status
  into v_total_rounds, v_couple_id, v_is_daily, v_initiator_id, v_status
  from public.game_sessions where id = new.session_id;

  if v_status in ('abandoned', 'archived') then
    return new;
  end if;

  if v_couple_id is null then
    select count(distinct round_number) into v_solo_count
    from public.game_responses
    where session_id = new.session_id and responder_id = v_initiator_id;

    v_both_complete := v_solo_count >= v_total_rounds;

    update public.game_sessions
    set started_at = coalesce(started_at, now()),
        updated_at = now(),
        status = (case when v_both_complete then 'completed' else 'active' end)::public.game_status,
        completed_at = case when v_both_complete then coalesce(completed_at, now()) else completed_at end
    where id = new.session_id;

    return new;
  end if;

  select partner_a_id, partner_b_id into v_partner_a_id, v_partner_b_id
  from public.couples where id = v_couple_id;

  select count(distinct round_number) into v_partner_a_count
  from public.game_responses
  where session_id = new.session_id and responder_id = v_partner_a_id;

  select count(distinct round_number) into v_partner_b_count
  from public.game_responses
  where session_id = new.session_id and responder_id = v_partner_b_id;

  v_both_complete := v_partner_a_count >= v_total_rounds and v_partner_b_count >= v_total_rounds;

  update public.game_sessions
  set started_at = coalesce(started_at, now()),
      updated_at = now(),
      status = (case when v_both_complete then 'completed' else 'active' end)::public.game_status,
      completed_at = case when v_both_complete then coalesce(completed_at, now()) else completed_at end
  where id = new.session_id;

  if v_is_daily and v_both_complete then
    -- The day the *session* belongs to, not whatever day either partner is currently in.
    -- With per-partner boundaries the two can disagree by up to a day, and crediting the
    -- streak to the responder's own "today" would let the same session bump two different
    -- dates depending on who finished it second. The session's date is the one both people
    -- were answering for.
    select daily_local_date into v_local_date
    from public.game_sessions where id = new.session_id;

    insert into public.daily_streaks (couple_id, current_streak, longest_streak, last_answered_date, updated_at)
    values (v_couple_id, 1, 1, v_local_date, now())
    on conflict (couple_id) do update set
      current_streak = case
        when public.daily_streaks.last_answered_date = v_local_date then public.daily_streaks.current_streak
        when public.daily_streaks.last_answered_date = v_local_date - 1 then public.daily_streaks.current_streak + 1
        else 1
      end,
      longest_streak = greatest(
        public.daily_streaks.longest_streak,
        case
          when public.daily_streaks.last_answered_date = v_local_date then public.daily_streaks.current_streak
          when public.daily_streaks.last_answered_date = v_local_date - 1 then public.daily_streaks.current_streak + 1
          else 1
        end
      ),
      last_answered_date = v_local_date,
      updated_at = now();
  end if;

  return new;
end;
$function$;

-- Abandoning ends only a game still being played.
--
-- A session that has already ended — completed, abandoned by the partner, archived by the cron —
-- is left as it is and the call returns quietly: it is over either way, and the person tapping
-- Abandon on a board their partner abandoned a moment ago has done nothing wrong. A completed
-- session in particular keeps its result. Who may call it is unchanged from 20261010000300, and a
-- session the caller cannot see still raises.
create or replace function public.abandon_game_session(p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status public.game_status;
begin
  select gs.status into v_status
  from public.game_sessions gs
  where gs.id = p_session_id
    and (
      (gs.couple_id is not null and public.is_couple_member(gs.couple_id))
      or (gs.couple_id is null and gs.initiator_id = auth.uid())
    )
  for update;

  if not found then
    -- Covers a session that does not exist and one belonging to somebody else, without
    -- distinguishing them: which of the two it is would tell a caller whether a given id is real.
    raise exception 'No such game session' using errcode = '42501';
  end if;

  if v_status in ('draft', 'active', 'waiting_for_partner') then
    update public.game_sessions
    set status = 'abandoned', updated_at = now()
    where id = p_session_id;
  end if;
end;
$$;

revoke all on function public.abandon_game_session(uuid) from public;
grant execute on function public.abandon_game_session(uuid) to authenticated;
