-- Same fix as 20260904000000, applied to the earlier "Keep your streak going" nudge — it had the
-- identical bug (fixed 18:00 UTC for every couple, when the real per-couple day boundary moved
-- off shared-UTC-midnight back in 20260829000500_daily_streak_per_couple_boundary.sql), just
-- lower-impact since a loose "still time today" nudge lands fine within a few hours' slop, unlike
-- the final one's explicit "1 hour left" promise.
--
-- 18:00 UTC was originally "6 hours before the day ends" (back when the boundary was a shared
-- UTC midnight) — moves to every 15 minutes, computing that same "6 hours before *this couple's*
-- boundary" relationship individually per couple, same as the final reminder now does for its own
-- 1-hour mark. early_reminder_sent_day_index de-dupes across the multiple qualifying 15-minute
-- runs the same way final_reminder_sent_day_index already does.
alter table public.daily_streaks
  add column early_reminder_sent_day_index int;

select cron.schedule('send-streak-reminders', '*/15 * * * *', 'select private.trigger_send_streak_reminders();');
