-- Buying back a streak that broke yesterday.
--
-- Two things carry real consequence and get most of the assertions: the window, because it decides
-- whether someone is offered a purchase at all, and the credit, because without it the repair is
-- free and the product is a decoration.
--
-- The window is asserted at both edges rather than in the middle. A repair offered a day late sells
-- something that cannot work; one offered a day early sells something that was not needed.

begin;
select plan(18);

create extension if not exists pgtap;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaaaaaa-8888-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ann@streak.test', 'x', now(), now()),
  ('aaaaaaaa-8888-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ben@streak.test', 'x', now(), now())
on conflict do nothing;

insert into public.couples (id, partner_a_id, partner_b_id, status)
values ('cccccccc-8888-0000-0000-00000000000c',
        'aaaaaaaa-8888-0000-0000-00000000000a',
        'aaaaaaaa-8888-0000-0000-00000000000b',
        'active');

-- Both partners on UTC, so the couple's local date is today and the arithmetic below is readable.
update public.profiles set timezone = 'UTC'
where id in ('aaaaaaaa-8888-0000-0000-00000000000a', 'aaaaaaaa-8888-0000-0000-00000000000b');

select set_config('test.today', (select local_date::text from private.couple_day('cccccccc-8888-0000-0000-00000000000c')), true);

insert into public.daily_streaks (couple_id, current_streak, longest_streak, last_answered_date, updated_at)
values ('cccccccc-8888-0000-0000-00000000000c', 27, 40,
        current_setting('test.today')::date - 2, now());

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-8888-0000-0000-00000000000a","role":"authenticated"}';

select is(
  (select repairable from public.streak_repair_state()),
  true, 'a streak that lapsed at yesterday''s midnight is repairable'
);
select is(
  (select streak_at_risk from public.streak_repair_state()),
  27, 'and the app can say what is at stake'
);
select is(
  (select missed_date from public.streak_repair_state()),
  current_setting('test.today')::date - 1, 'naming the day that was missed'
);

-- Not yet broken.
reset role;
update public.daily_streaks set last_answered_date = current_setting('test.today')::date - 1
where couple_id = 'cccccccc-8888-0000-0000-00000000000c';
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-8888-0000-0000-00000000000a","role":"authenticated"}';

select is(
  (select repairable from public.streak_repair_state()),
  false, 'a streak still going is not offered a repair'
);

-- Answered today already.
reset role;
update public.daily_streaks set last_answered_date = current_setting('test.today')::date
where couple_id = 'cccccccc-8888-0000-0000-00000000000c';
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-8888-0000-0000-00000000000a","role":"authenticated"}';

select is(
  (select repairable from public.streak_repair_state()),
  false, 'nor one that has already been kept today'
);

-- Too old.
reset role;
update public.daily_streaks set last_answered_date = current_setting('test.today')::date - 3
where couple_id = 'cccccccc-8888-0000-0000-00000000000c';
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-8888-0000-0000-00000000000a","role":"authenticated"}';

select is(
  (select repairable from public.streak_repair_state()),
  false, 'two missed days is past the window'
);
select is(
  (select error_message from public.repair_couple_streak()),
  'This streak has been broken for too long to repair.',
  'and repairing it is refused outright'
);

-- ---------------------------------------------------------------------------
-- Without a credit there is no repair
-- ---------------------------------------------------------------------------

reset role;
update public.daily_streaks set last_answered_date = current_setting('test.today')::date - 2
where couple_id = 'cccccccc-8888-0000-0000-00000000000c';
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-8888-0000-0000-00000000000a","role":"authenticated"}';

select is(
  (select error_message from public.repair_couple_streak()),
  'no_credit', 'in the window but unpaid, the repair is refused'
);
select is(
  (select last_answered_date from public.daily_streaks where couple_id = 'cccccccc-8888-0000-0000-00000000000c'),
  current_setting('test.today')::date - 2, 'and nothing moved'
);

-- A client cannot write itself one.
select throws_ok(
  $$ insert into public.streak_repair_credits (profile_id, transaction_id)
     values ('aaaaaaaa-8888-0000-0000-00000000000a', 'forged-1') $$,
  null,
  null,
  'a client cannot grant itself a credit'
);

-- ---------------------------------------------------------------------------
-- With one, it works — once
-- ---------------------------------------------------------------------------

reset role;
select is(private.grant_streak_repair_credit('aaaaaaaa-8888-0000-0000-00000000000a', 'txn-1'), true,
  'the webhook grants a credit');
select is(private.grant_streak_repair_credit('aaaaaaaa-8888-0000-0000-00000000000a', 'txn-1'), false,
  'and a redelivery of the same transaction grants nothing further');
select is(
  (select count(*)::integer from public.streak_repair_credits where profile_id = 'aaaaaaaa-8888-0000-0000-00000000000a'),
  1, 'leaving exactly one credit'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-8888-0000-0000-00000000000a","role":"authenticated"}';

select is(
  (select repaired from public.repair_couple_streak()),
  true, 'with a credit, the repair goes through'
);

-- Yesterday, not today: the stored streak shows again, and today's answer still counts.
select is(
  (select last_answered_date from public.daily_streaks where couple_id = 'cccccccc-8888-0000-0000-00000000000c'),
  current_setting('test.today')::date - 1, 'the gap is bridged to yesterday, not to today'
);

select is(
  (select current_streak from public.get_daily_streak()),
  27, 'so the streak is visible again, at the number it was'
);

-- The credit is spent.
select is(
  (select error_message from public.repair_couple_streak()),
  'Your streak is still going.',
  'and repairing again is refused — there is nothing broken now'
);

reset role;
select is(
  (select count(*)::integer from public.streak_repair_credits
   where profile_id = 'aaaaaaaa-8888-0000-0000-00000000000a' and consumed_at is null),
  0, 'the credit was spent, not left lying around'
);

select * from finish();
rollback;
