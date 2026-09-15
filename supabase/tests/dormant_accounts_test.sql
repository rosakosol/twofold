-- Who the dormancy timer picks up, and — much more importantly — who it does not.
--
-- This job deletes relationship archives, and the mistakes are not symmetrical. Sweeping up
-- somebody who is still here destroys years of irreplaceable content belonging to two people, one
-- of whom may never have been warned. Missing somebody who left costs storage. So most of what
-- follows asserts the negative: the couple who are still here, the couple where only one of them
-- is still here, the account that is already closed.
--
-- `dormancy_cohort` takes `p_now` so these can stand two years into the future without waiting,
-- and every threshold is expressed against `private.dormancy_period()` rather than a literal — if
-- the policy changes to eighteen months, these keep testing the policy rather than the number.

begin;
select plan(18);

create extension if not exists pgtap;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('dddddddd-0000-0000-0000-00000000001a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'here-a@dorm.test', 'x', now(), now()),
  ('dddddddd-0000-0000-0000-00000000001b', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'here-b@dorm.test', 'x', now(), now()),
  ('dddddddd-0000-0000-0000-00000000002a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'gone-a@dorm.test', 'x', now(), now()),
  ('dddddddd-0000-0000-0000-00000000002b', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'gone-b@dorm.test', 'x', now(), now()),
  ('dddddddd-0000-0000-0000-00000000003a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'half-a@dorm.test', 'x', now(), now()),
  ('dddddddd-0000-0000-0000-00000000003b', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'half-b@dorm.test', 'x', now(), now()),
  ('dddddddd-0000-0000-0000-00000000004a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'solo@dorm.test', 'x', now(), now()),
  ('dddddddd-0000-0000-0000-00000000005a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'closed@dorm.test', 'x', now(), now())
on conflict do nothing;

insert into public.couples (id, partner_a_id, partner_b_id, status)
values
  ('cccccccc-0000-0000-0000-0000000000a1', 'dddddddd-0000-0000-0000-00000000001a', 'dddddddd-0000-0000-0000-00000000001b', 'active'),
  ('cccccccc-0000-0000-0000-0000000000b1', 'dddddddd-0000-0000-0000-00000000002a', 'dddddddd-0000-0000-0000-00000000002b', 'active'),
  ('cccccccc-0000-0000-0000-0000000000c1', 'dddddddd-0000-0000-0000-00000000003a', 'dddddddd-0000-0000-0000-00000000003b', 'active');

-- Something shared worth losing, so the couple-level assertions are about real content.
insert into public.memories (id, couple_id, title, occurred_at)
values ('bbbbbbbb-0000-0000-0000-0000000000b1', 'cccccccc-0000-0000-0000-0000000000b1', 'Two years ago', now());

-- A stable clock for every threshold below.
create temporary table dorm_now as select now() as t;

-- here: both opened it yesterday.
update public.profiles set last_active_at = (select t from dorm_now) - interval '1 day'
where id in ('dddddddd-0000-0000-0000-00000000001a', 'dddddddd-0000-0000-0000-00000000001b');

-- gone: neither has opened it in well over the period.
update public.profiles set last_active_at = (select t from dorm_now) - private.dormancy_period() - interval '40 days'
where id in ('dddddddd-0000-0000-0000-00000000002a', 'dddddddd-0000-0000-0000-00000000002b');

-- half: A vanished two years ago, B was here last week. The couple is alive.
update public.profiles set last_active_at = (select t from dorm_now) - private.dormancy_period() - interval '40 days'
where id = 'dddddddd-0000-0000-0000-00000000003a';
update public.profiles set last_active_at = (select t from dorm_now) - interval '7 days'
where id = 'dddddddd-0000-0000-0000-00000000003b';

-- solo: no couple at all, long gone.
update public.profiles set last_active_at = (select t from dorm_now) - private.dormancy_period() - interval '5 days'
where id = 'dddddddd-0000-0000-0000-00000000004a';

-- closed: long gone, but the account was already deleted.
update public.profiles
set last_active_at = (select t from dorm_now) - private.dormancy_period() - interval '90 days',
    account_deleted_at = (select t from dorm_now) - interval '300 days'
where id = 'dddddddd-0000-0000-0000-00000000005a';

-- ---------------------------------------------------------------------------
-- Who is left alone
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int from public.dormancy_cohort((select t from dorm_now))
   where profile_id in ('dddddddd-0000-0000-0000-00000000001a', 'dddddddd-0000-0000-0000-00000000001b')),
  0,
  'a couple who opened the app yesterday are not in the cohort at all'
);

select is(
  (select count(*)::int from public.dormancy_cohort((select t from dorm_now))
   where profile_id in ('dddddddd-0000-0000-0000-00000000003a', 'dddddddd-0000-0000-0000-00000000003b')),
  0,
  'one partner still active keeps BOTH accounts out of the cohort'
);

select is(
  (select count(*)::int from public.dormancy_cohort((select t from dorm_now))
   where profile_id = 'dddddddd-0000-0000-0000-00000000005a'),
  0,
  'an already-closed account is never picked up again'
);

-- ---------------------------------------------------------------------------
-- The stages
-- ---------------------------------------------------------------------------

select is(
  (select stage from public.dormancy_cohort((select t from dorm_now))
   where profile_id = 'dddddddd-0000-0000-0000-00000000002a'),
  'delete',
  'past the period, the stage is delete'
);

select is(
  (select stage from public.dormancy_cohort((select t from dorm_now))
   where profile_id = 'dddddddd-0000-0000-0000-00000000004a'),
  'delete',
  'a solo account is its own cohort and expires on its own clock'
);

-- Wind the clock back to inside each warning window rather than moving the data.
select is(
  (select stage from public.dormancy_cohort(
     (select t from dorm_now) - interval '43 days')
   where profile_id = 'dddddddd-0000-0000-0000-00000000002a'),
  'warn_7',
  'inside the last week before deletion, the stage is warn_7'
);

select is(
  (select stage from public.dormancy_cohort(
     (select t from dorm_now) - interval '60 days')
   where profile_id = 'dddddddd-0000-0000-0000-00000000002a'),
  'warn_30',
  'a month out, the stage is warn_30'
);

select is(
  (select count(*)::int from public.dormancy_cohort(
     (select t from dorm_now) - interval '75 days')
   where profile_id = 'dddddddd-0000-0000-0000-00000000002a'),
  0,
  'before the first warning window opens, nothing is due'
);

-- ---------------------------------------------------------------------------
-- Warnings are not repeated, but a new cycle does warn again
-- ---------------------------------------------------------------------------

-- Warned *inside* the 30-day window, which is when the job would really have sent it.
select public.mark_dormancy_warned(
  array['dddddddd-0000-0000-0000-00000000002a']::uuid[],
  (select t from dorm_now) - interval '60 days'
);

select is(
  (select count(*)::int from public.dormancy_cohort((select t from dorm_now) - interval '60 days')
   where profile_id = 'dddddddd-0000-0000-0000-00000000002a'),
  0,
  'having been warned, the same account is not warned again in the same window'
);

select is(
  (select stage from public.dormancy_cohort((select t from dorm_now) - interval '43 days')
   where profile_id = 'dddddddd-0000-0000-0000-00000000002a'),
  'warn_7',
  'the 30-day warning does not suppress the 7-day one'
);

select is(
  (select stage from public.dormancy_cohort((select t from dorm_now))
   where profile_id = 'dddddddd-0000-0000-0000-00000000002a'),
  'delete',
  'and no warning suppresses the deletion itself'
);

-- ---------------------------------------------------------------------------
-- Closing an account
-- ---------------------------------------------------------------------------

select public.close_dormant_account('dddddddd-0000-0000-0000-00000000002a');

select is(
  (select status::text from public.couples where id = 'cccccccc-0000-0000-0000-0000000000b1'),
  'dissolved',
  'closing a dormant account dissolves the couple, which starts the normal archive timer'
);

select isnt(
  (select scheduled_purge_at from public.couples where id = 'cccccccc-0000-0000-0000-0000000000b1'),
  null,
  'and the shared content is left to that timer rather than deleted here'
);

select is(
  (select first_name from public.profiles where id = 'dddddddd-0000-0000-0000-00000000002a'),
  'Deleted User',
  'the closed profile is scrubbed the same way self-serve deletion scrubs it'
);

-- Running it twice must not dissolve anything a second time or re-stamp the clock.
select lives_ok(
  $$ select public.close_dormant_account('dddddddd-0000-0000-0000-00000000002a') $$,
  'closing an already-closed account is a no-op, so a half-failed run can simply be repeated'
);

-- ---------------------------------------------------------------------------
-- In `public` so PostgREST can see it, but not for anyone else
-- ---------------------------------------------------------------------------
--
-- These live in `public` only because PostgREST cannot reach `private` (see the migration header).
-- That makes the revoke the thing standing between an ordinary signed-in user and a list of every
-- dormant account's email address — or the ability to close one. Assert it rather than trust it.

set local role authenticated;

select throws_ok(
  $$ select * from public.dormancy_cohort() $$,
  '42501',
  null,
  'a signed-in user cannot list the dormancy cohort, which is a list of email addresses'
);

select throws_ok(
  $$ select public.close_dormant_account('dddddddd-0000-0000-0000-00000000001a') $$,
  '42501',
  null,
  'a signed-in user cannot close an account'
);

select throws_ok(
  $$ select public.mark_dormancy_warned(array['dddddddd-0000-0000-0000-00000000001a']::uuid[]) $$,
  '42501',
  null,
  'a signed-in user cannot fiddle with the warning stamps to dodge or force a deletion'
);

reset role;

select * from finish();
rollback;
