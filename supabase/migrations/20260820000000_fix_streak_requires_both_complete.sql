-- Fixes advance_game_session (20260713040000): the daily_streaks block fired whenever *either*
-- partner answered the daily question, not just once both had — so the streak incremented (and
-- could even be created) with only one side answered. v_both_complete was already being computed
-- for the session-status update right above; the streak block just wasn't gated on it.
create or replace function public.advance_game_session()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total_rounds int;
  v_couple_id uuid;
  v_partner_a_id uuid;
  v_partner_b_id uuid;
  v_partner_a_count int;
  v_partner_b_count int;
  v_both_complete boolean;
  v_is_daily boolean;
begin
  select total_rounds, couple_id, is_daily into v_total_rounds, v_couple_id, v_is_daily
  from public.game_sessions where id = new.session_id;

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
    insert into public.daily_streaks (couple_id, current_streak, longest_streak, last_answered_date, updated_at)
    values (v_couple_id, 1, 1, current_date, now())
    on conflict (couple_id) do update set
      current_streak = case
        when public.daily_streaks.last_answered_date = current_date then public.daily_streaks.current_streak
        when public.daily_streaks.last_answered_date = current_date - 1 then public.daily_streaks.current_streak + 1
        else 1
      end,
      longest_streak = greatest(
        public.daily_streaks.longest_streak,
        case
          when public.daily_streaks.last_answered_date = current_date then public.daily_streaks.current_streak
          when public.daily_streaks.last_answered_date = current_date - 1 then public.daily_streaks.current_streak + 1
          else 1
        end
      ),
      last_answered_date = current_date,
      updated_at = now();
  end if;

  return new;
end;
$$;
