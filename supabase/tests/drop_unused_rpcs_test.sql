-- 20261120000000 drops three functions nothing called. Pinned here: those three are gone, and the
-- neighbours that looked like them, and were kept on purpose, are still there and still run.

begin;
select plan(10);

create extension if not exists pgtap;

-- Gone.
select hasnt_function('public'::name, 'list_couple_day_bounds'::name,
  'list_couple_day_bounds is gone; the reminder cron reads list_streak_reminder_targets');
select hasnt_function('public'::name, 'delete_dissolved_couple_data'::name,
  'delete_dissolved_couple_data is gone; archives are only purged when their 90 days are up');
select hasnt_function('public'::name, 'mark_discussion_round'::name,
  'mark_discussion_round is gone');

-- Kept: the daily-question pair that builds in the field still call.
select has_function('public'::name, 'get_daily_question_session'::name, array[]::name[],
  'get_daily_question_session stays: get_daily_question calls it, and so do shipped builds');
select has_function('public'::name, 'get_daily_question_status'::name, array[]::name[],
  'get_daily_question_status stays for shipped builds');
select has_function('public'::name, 'get_daily_question'::name, array[]::name[],
  'get_daily_question is still there');

-- Kept: what replaced list_couple_day_bounds, and the day helper streak repair uses.
select has_function('public'::name, 'list_streak_reminder_targets'::name, array[]::name[],
  'list_streak_reminder_targets is still there');
select has_function('private'::name, 'couple_day'::name, array['uuid', 'timestamp with time zone']::name[],
  'private.couple_day is still there');
select lives_ok(
  $$ select * from private.couple_day(gen_random_uuid(), now()) $$,
  'and still runs'
);

set local role service_role;
select lives_ok(
  $$ select count(*) from public.list_streak_reminder_targets() $$,
  'the reminder cron can still read its targets'
);
reset role;

-- The feedback-board outbox this migration kept was dropped later, by 20261120000100.

select * from finish();
rollback;
