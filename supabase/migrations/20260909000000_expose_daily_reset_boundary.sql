-- The Games hub's daily-streak card counts down to the next reset ("Next in 03:12:45"). That
-- countdown was computed client-side from `couples.created_at` using the old anchor-relative
-- day-index math (see DailyActivityCard.countdownLabel, whose comment claimed it "mirrors the
-- trigger's own floor((now - connectedAt) / 86400) math exactly"). 20260908000000 moved the real
-- boundary to local midnight, which silently made that claim false - the timer kept counting down
-- to the couple's old pairing time while the streak actually rolled at midnight.
--
-- Rather than re-derive local midnight on the client (which for a couple means knowing *both*
-- partners' timezones, and duplicating the greatest()-of-two-midnights rule), the boundary is
-- returned alongside the streak it belongs to. One source of truth, same as
-- list_couple_day_bounds did for the reminder function.
--
-- Also returns a row for solo (unpaired) users now - they answer the daily question too, and
-- previously got no row at all because this joined `couples`. They get 0/0 plus their own
-- boundary, so the countdown can work for them as well.

-- Return type changes (new OUT column), so this can't be a plain create-or-replace.
drop function if exists public.get_daily_streak();

create function public.get_daily_streak()
returns table (current_streak int, longest_streak int, next_boundary timestamptz)
language sql
security definer
stable
set search_path = public
as $$
  select
    coalesce(
      case
        when ds.last_answered_date is null then 0
        -- Same "still alive" rule the increment side uses (20260907000000): answered today, or
        -- yesterday and therefore still continuable today.
        when ds.last_answered_date >= vd.local_date - 1 then ds.current_streak
        else 0
      end,
      0
    )::int as current_streak,
    coalesce(ds.longest_streak, 0)::int as longest_streak,
    vd.next_boundary
  from private.viewer_day() vd
  left join public.daily_streaks ds on ds.couple_id = vd.couple_id;
$$;

revoke all on function public.get_daily_streak() from public;
grant execute on function public.get_daily_streak() to authenticated;
