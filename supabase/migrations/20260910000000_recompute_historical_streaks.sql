-- One-time data correction for streaks inflated by a real bug.
--
-- 20260820000000 deliberately gated the streak on `v_both_complete` ("both partners answered"),
-- but 20260829000500 rewrote advance_game_session to move the day boundary and silently dropped
-- that gate; 20260901001700 carried the regression forward. Until 20260907000000 restored it, the
-- streak advanced as soon as *one* partner answered - so couples hold streaks the other person
-- never participated in. Restoring the gate stopped new inflation but left the accrued numbers.
--
-- This recomputes current_streak / longest_streak / last_answered_date from `game_responses`,
-- which is the actual source of truth, rather than trying to unwind the bad increments. A day
-- counts only if BOTH partners met the session's total_rounds - the same rule advance_game_session
-- enforces now.
--
-- Day identity comes from game_sessions.daily_local_date. For historical sessions that column was
-- backfilled (20260908000000) from the same anchor math that originally created them, so this
-- groups days exactly the way the old system did rather than inventing new boundaries.
--
-- Deliberately corrects longest_streak too, not just current_streak: a "longest" derived from days
-- one partner never answered isn't a record of anything that happened.

with sess as (
  select gs.id, gs.couple_id, gs.daily_local_date as d, gs.total_rounds,
         c.partner_a_id, c.partner_b_id
  from public.game_sessions gs
  join public.couples c on c.id = gs.couple_id
  where gs.is_daily and gs.daily_local_date is not null
),
counts as (
  select s.couple_id, s.d, max(s.total_rounds) as total_rounds,
         count(distinct gr.round_number) filter (where gr.responder_id = s.partner_a_id) as a_cnt,
         count(distinct gr.round_number) filter (where gr.responder_id = s.partner_b_id) as b_cnt
  from sess s
  left join public.game_responses gr on gr.session_id = s.id
  group by s.couple_id, s.d
),
qualified as (
  select couple_id, d from counts
  where a_cnt >= total_rounds and b_cnt >= total_rounds
),
-- Classic gaps-and-islands: consecutive dates share (date - row_number), so each distinct value
-- of `grp` is one unbroken run of days.
runs as (
  select couple_id, d,
         d - (row_number() over (partition by couple_id order by d))::int as grp
  from qualified
),
run_lengths as (
  select couple_id, grp, count(*)::int as len, max(d) as run_end
  from runs group by couple_id, grp
),
computed as (
  select rl.couple_id,
         max(rl.len) as longest,
         -- Same "still alive" rule as get_daily_streak: a run counts as current only if it ends
         -- today or yesterday (yesterday still being continuable today).
         coalesce(max(rl.len) filter (
           where rl.run_end >= (select local_date from private.couple_day(rl.couple_id)) - 1
         ), 0) as current,
         max(rl.run_end) as last_answered
  from run_lengths rl
  group by rl.couple_id
)
update public.daily_streaks ds
set current_streak = coalesce(cp.current, 0),
    longest_streak = coalesce(cp.longest, 0),
    last_answered_date = cp.last_answered,
    updated_at = now()
from (select couple_id from public.daily_streaks) all_rows
left join computed cp on cp.couple_id = all_rows.couple_id
where ds.couple_id = all_rows.couple_id;
