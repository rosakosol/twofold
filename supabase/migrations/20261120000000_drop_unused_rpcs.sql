-- Drops three functions nothing calls any more.
--
-- Each was checked before it went: no caller in the app (Twofold/), the site (site/src, apart from
-- the generated db/types.ts), any edge function, any cron job, or the body of any other database
-- function (pg_proc.prosrc, on a stack with every migration applied).
--
--   * list_couple_day_bounds() — the streak-reminder cohort before per-partner day boundaries.
--     20260912000100 left it "in place but unused" until send-streak-reminders moved to
--     list_streak_reminder_targets, which it has. private.couple_day stays: streak repair uses it.
--   * delete_dissolved_couple_data(uuid) — the one-sided early delete of a dissolved couple's data.
--     There is no early delete any more (see archive_hide_and_no_early_purge_test); a shared archive
--     goes when its 90 days are up, through purge_couple_data.
--   * mark_discussion_round(uuid, text) — from the first games schema. 20261108000000 already took it
--     away from clients; nothing on the server ever called it.
--
-- Kept, on purpose:
--   * get_daily_question_session() and get_daily_question_status(). get_daily_question() calls the
--     first, and builds of the app already in people's hands call both.
--   * feature_notification_outbox and the two triggers that fill it. Nothing reads it yet, but it
--     is a table that may hold rows in production, so whether to drop it is the owner's decision,
--     not a cleanup's.

drop function if exists public.list_couple_day_bounds();
drop function if exists public.delete_dissolved_couple_data(uuid);
drop function if exists public.mark_discussion_round(uuid, text);
