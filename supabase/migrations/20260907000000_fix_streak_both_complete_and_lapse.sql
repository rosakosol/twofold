-- Two related daily-streak bugs.
--
-- 1. `advance_game_session` lost its "both partners must have answered" gate. 20260820000000_fix_
--    streak_requires_both_complete.sql deliberately added `and v_both_complete` (its whole point —
--    see its header), but 20260829000500_daily_streak_per_couple_boundary.sql rewrote the function
--    to move the day boundary and silently dropped the gate back to a bare `if v_is_daily then`,
--    and 20260901001700_solo_game_sessions.sql carried that regression forward. Net effect: the
--    streak incremented as soon as *one* partner answered, so a couple could hold a streak the
--    other person never participated in. Restores the gate (keeping the solo-session early-return
--    branch 20260901001700 added).
--
-- 2. `current_streak` is only ever recomputed inside this trigger — i.e. only when someone
--    answers. Nothing resets it when a day simply lapses, so a couple who last answered days ago
--    still reads back their old `current_streak` until the next answer lazily hits the `else 1`
--    branch. That's the "streak continues even if a day is missed" report: the stored number is
--    fine as a *last-known* value, but it's wrong to display raw. `get_daily_streak()` below is
--    the read path that applies the lapse rule, so display and increment agree on one definition
--    of "still alive" (answered today, or yesterday and still able to continue today).

create or replace function public.advance_game_session()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total_rounds int;
  v_couple_id uuid;
  v_initiator_id uuid;
  v_partner_a_id uuid;
  v_partner_b_id uuid;
  v_partner_a_count int;
  v_partner_b_count int;
  v_solo_count int;
  v_both_complete boolean;
  v_is_daily boolean;
  v_couple_created_at timestamptz;
  v_day_index int;
begin
  select total_rounds, couple_id, is_daily, initiator_id
  into v_total_rounds, v_couple_id, v_is_daily, v_initiator_id
  from public.game_sessions where id = new.session_id;

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

  select partner_a_id, partner_b_id, created_at into v_partner_a_id, v_partner_b_id, v_couple_created_at
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

  -- `and v_both_complete` restored — see this migration's header (bug 1).
  if v_is_daily and v_both_complete then
    v_day_index := floor(extract(epoch from (now() - v_couple_created_at)) / 86400)::int;

    insert into public.daily_streaks (couple_id, current_streak, longest_streak, last_answered_day_index, updated_at)
    values (v_couple_id, 1, 1, v_day_index, now())
    on conflict (couple_id) do update set
      current_streak = case
        when public.daily_streaks.last_answered_day_index = v_day_index then public.daily_streaks.current_streak
        when public.daily_streaks.last_answered_day_index = v_day_index - 1 then public.daily_streaks.current_streak + 1
        else 1
      end,
      longest_streak = greatest(
        public.daily_streaks.longest_streak,
        case
          when public.daily_streaks.last_answered_day_index = v_day_index then public.daily_streaks.current_streak
          when public.daily_streaks.last_answered_day_index = v_day_index - 1 then public.daily_streaks.current_streak + 1
          else 1
        end
      ),
      last_answered_day_index = v_day_index,
      updated_at = now();
  end if;

  return new;
end;
$$;

-- The read path for the streak (bug 2). Applies the same "still alive" rule the increment above
-- uses, so a lapsed streak reads 0 instead of its stale last-known value the moment the day it
-- could still have been continued on passes:
--   * answered today (day_index)      -> alive, show it
--   * answered yesterday (day_index-1) -> alive, still continuable today, show it
--   * anything older / never answered  -> lapsed, show 0
-- `longest_streak` is a historical high-water mark and deliberately never decays.
create or replace function public.get_daily_streak()
returns table (current_streak int, longest_streak int)
language sql
security definer
stable
set search_path = public
as $$
  select
    (case
      when ds.last_answered_day_index is null then 0
      when ds.last_answered_day_index >= floor(extract(epoch from (now() - c.created_at)) / 86400)::int - 1
        then ds.current_streak
      else 0
    end)::int as current_streak,
    ds.longest_streak
  from public.daily_streaks ds
  join public.couples c on c.id = ds.couple_id
  where public.is_couple_member(ds.couple_id)
  limit 1;
$$;

revoke all on function public.get_daily_streak() from public;
grant execute on function public.get_daily_streak() to authenticated;
