-- One daily question session per couple per day.
--
-- `get_daily_question_session()` is a check-then-insert with real work in the gap (tier lookup,
-- `order by random()` over the content table). Nothing used to stop two concurrent callers both
-- seeing "no session yet" and both inserting — and the streak reminder cron nudges both partners of
-- a same-timezone couple in the same run, so the two people are prompted at the same second.
--
-- Two sessions for one date breaks the streak silently: each partner answers a different row, so
-- `advance_game_session`'s both-complete gate never fires and the streak just doesn't advance, with
-- no error anywhere. See 20260913000000_daily_session_unique_per_day.sql.

begin;
select plan(9);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-2222-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@daily.test', 'x', now(), now(), now()),
  ('bbbbbbbb-2222-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@daily.test', 'x', now(), now(), now()),
  ('dddddddd-2222-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'solo@daily.test', 'x', now(), now(), now());

-- A trigger on auth.users already created these rows; fill in what the tests care about.
insert into public.profiles (id, first_name, timezone) values
  ('aaaaaaaa-2222-0000-0000-000000000001', 'Ada', 'UTC'),
  ('bbbbbbbb-2222-0000-0000-000000000002', 'Mel', 'UTC'),
  ('dddddddd-2222-0000-0000-000000000004', 'Sol', 'UTC')
on conflict (id) do update set first_name = excluded.first_name, timezone = excluded.timezone;

insert into public.couples (id, partner_a_id, partner_b_id)
values ('cccccccc-2222-0000-0000-000000000003', 'aaaaaaaa-2222-0000-0000-000000000001', 'bbbbbbbb-2222-0000-0000-000000000002');

-- ---------------------------------------------------------------------------
-- The index itself.
-- ---------------------------------------------------------------------------

insert into public.game_sessions (id, couple_id, initiator_id, game_type, status, is_daily, daily_local_date, total_rounds)
values ('11111111-2222-0000-0000-000000000001', 'cccccccc-2222-0000-0000-000000000003',
        'aaaaaaaa-2222-0000-0000-000000000001', 'deep_conversations', 'active', true, date '2026-09-20', 1);

-- The whole point: the second partner's concurrent insert must not be allowed to land.
select throws_ok(
  $$insert into public.game_sessions (couple_id, initiator_id, game_type, status, is_daily, daily_local_date, total_rounds)
    values ('cccccccc-2222-0000-0000-000000000003', 'bbbbbbbb-2222-0000-0000-000000000002',
            'deep_conversations', 'active', true, date '2026-09-20', 1)$$,
  '23505',
  null,
  'a second daily session for the same couple and date is rejected'
);

-- `on conflict do nothing` is what the RPC relies on to turn that rejection into a no-op, so the
-- loser of the race can fall back to reading the winner's session instead of erroring.
select lives_ok(
  $$insert into public.game_sessions (couple_id, initiator_id, game_type, status, is_daily, daily_local_date, total_rounds)
    values ('cccccccc-2222-0000-0000-000000000003', 'bbbbbbbb-2222-0000-0000-000000000002',
            'deep_conversations', 'active', true, date '2026-09-20', 1)
    on conflict do nothing$$,
  'on conflict do nothing turns the duplicate into a no-op rather than an error'
);

select is(
  (select count(*)::int from public.game_sessions
   where couple_id = 'cccccccc-2222-0000-0000-000000000003' and daily_local_date = date '2026-09-20'),
  1,
  'still exactly one session for that date'
);

-- A different date is a different session — the index must not block tomorrow.
select lives_ok(
  $$insert into public.game_sessions (couple_id, initiator_id, game_type, status, is_daily, daily_local_date, total_rounds)
    values ('cccccccc-2222-0000-0000-000000000003', 'aaaaaaaa-2222-0000-0000-000000000001',
            'deep_conversations', 'active', true, date '2026-09-21', 1)$$,
  'the next day gets its own session'
);

-- Abandoning is how a reset frees the slot; the index predicate excludes abandoned rows precisely
-- so that re-creating the same day's session still works afterwards.
update public.game_sessions set status = 'abandoned'
where id = '11111111-2222-0000-0000-000000000001';

select lives_ok(
  $$insert into public.game_sessions (couple_id, initiator_id, game_type, status, is_daily, daily_local_date, total_rounds)
    values ('cccccccc-2222-0000-0000-000000000003', 'aaaaaaaa-2222-0000-0000-000000000001',
            'deep_conversations', 'active', true, date '2026-09-20', 1)$$,
  'abandoning the old session frees the date to be used again'
);

-- Solo (unpaired) sessions have a null couple_id, and null is never equal to null in a unique
-- index — so they need their own index keyed on the initiator, or they are unprotected.
insert into public.game_sessions (couple_id, initiator_id, game_type, status, is_daily, daily_local_date, total_rounds)
values (null, 'dddddddd-2222-0000-0000-000000000004', 'deep_conversations', 'active', true, date '2026-09-20', 1);

select throws_ok(
  $$insert into public.game_sessions (couple_id, initiator_id, game_type, status, is_daily, daily_local_date, total_rounds)
    values (null, 'dddddddd-2222-0000-0000-000000000004',
            'deep_conversations', 'active', true, date '2026-09-20', 1)$$,
  '23505',
  null,
  'a solo daily session is unique per initiator per date too'
);

-- ---------------------------------------------------------------------------
-- The RPC, as a real caller.
-- ---------------------------------------------------------------------------
-- Both partners asking for today's question must converge on one session. This is the behaviour
-- the whole fix exists to guarantee; it happens to also be what the non-racing path already did.
--
-- The assertions below spell the day out as `timezone('UTC', now())::date` rather than calling
-- `private.viewer_day()`: these run as `authenticated`, which has no rights on the `private` schema
-- (only the security-definer functions that wrap it do). Both profiles above are UTC, so the two
-- are the same date by construction.

set local role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-2222-0000-0000-000000000001', true);
select lives_ok(
  $$select public.get_daily_question_session()$$,
  'the first partner can open today''s question'
);

select set_config('request.jwt.claim.sub', 'bbbbbbbb-2222-0000-0000-000000000002', true);

select is(
  (select public.get_daily_question_session()),
  (select id from public.game_sessions
   where couple_id = 'cccccccc-2222-0000-0000-000000000003'
     and is_daily and status <> 'abandoned'
     and daily_local_date = timezone('UTC', now())::date),
  'the second partner is handed the same session, not a new one'
);

-- A session that picked up a second round would silently double the daily question's length — the
-- specific thing the "don't insert a round when you lost the race" branch protects against.
select is(
  (select count(*)::int from public.game_session_rounds gsr
   join public.game_sessions gs on gs.id = gsr.session_id
   where gs.couple_id = 'cccccccc-2222-0000-0000-000000000003'
     and gs.is_daily and gs.status <> 'abandoned'
     and gs.daily_local_date = timezone('UTC', now())::date),
  1,
  'today''s session has exactly one round after both partners opened it'
);

select * from finish();
rollback;
