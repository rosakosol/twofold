-- Fixes a real bug: the "1 hour left" reminder (20260902000000) was scheduled at a single fixed
-- 23:00 UTC for every couple, on the assumption "the streak's own day boundary is midnight UTC" —
-- true when that migration's comment was written, but 20260829000500_daily_streak_per_couple_
-- boundary.sql had *already* moved the real boundary to be relative to each couple's own
-- `couples.created_at` (a rolling 24h window from whenever they connected, not a shared calendar
-- day). A couple whose day rolls over at, say, 10:00 UTC got the "1 hour left!" push at 23:00 UTC
-- — 11+ hours before their real deadline, exactly the "10+ hours left" bug reported.
--
-- Moves the final-reminder cron to run every 15 minutes instead of once a day; send-streak-
-- reminders (updated alongside this migration) now computes each couple's own day boundary from
-- couples.created_at and only sends when that specific couple is genuinely within its last hour.
-- final_reminder_sent_day_index de-dupes across the multiple qualifying runs a 15-minute cadence
-- would otherwise produce for the same couple/day.
alter table public.daily_streaks
  add column final_reminder_sent_day_index int;

select cron.schedule('send-streak-ending-reminders', '*/15 * * * *', 'select private.trigger_send_streak_ending_reminders();');
