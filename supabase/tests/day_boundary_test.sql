-- Day-boundary helpers behind the daily question and streak reset.
--
-- These exist because streaks used to roll over at whatever wall-clock time the couple happened to
-- sign up — people were losing streaks at 9:45pm. The rule now is local midnight, and for a couple
-- it's the *later* of the two partners' local midnights, so neither person's day ends while the
-- other still has time to answer. That "later of the two" choice is subtle and easy to flip by
-- accident, so it's pinned here along with the timezone fallback.

begin;
select plan(13);

-- safe_timezone: anything Postgres can't resolve must fall back rather than raise, since this runs
-- inside functions that would otherwise fail closed and lock a couple out of their daily question.
select is(private.safe_timezone('Australia/Melbourne'), 'Australia/Melbourne', 'valid zone passes through');
select is(private.safe_timezone('Europe/London'), 'Europe/London', 'another valid zone passes through');
select is(private.safe_timezone(null), 'UTC', 'null falls back to UTC');
select is(private.safe_timezone(''), 'UTC', 'empty string falls back to UTC');
select is(private.safe_timezone('Mars/Olympus_Mons'), 'UTC', 'unknown zone falls back to UTC rather than raising');

-- local_date_at: the same instant is two different calendar dates either side of the dateline.
-- 2026-08-17 13:00 UTC is the 17th in London and already the 17th 11pm in Melbourne; two hours
-- later Melbourne has ticked over to the 18th while London is still on the 17th.
select is(
  private.local_date_at('Australia/Melbourne', '2026-08-17T15:00:00Z'::timestamptz),
  '2026-08-18'::date,
  'Melbourne is already on the next date at 15:00 UTC'
);
select is(
  private.local_date_at('Europe/London', '2026-08-17T15:00:00Z'::timestamptz),
  '2026-08-17'::date,
  'London is still on the previous date at the same instant'
);

-- next_local_midnight: strictly in the future, and it is the start of the next local day.
select ok(
  private.next_local_midnight('Europe/London', '2026-08-17T15:00:00Z'::timestamptz) > '2026-08-17T15:00:00Z'::timestamptz,
  'next local midnight is in the future'
);
select is(
  private.local_date_at('Europe/London', private.next_local_midnight('Europe/London', '2026-08-17T15:00:00Z'::timestamptz)),
  '2026-08-18'::date,
  'next local midnight lands on the following local date'
);

-- Fixtures for the couple-level helper: two partners 9 hours apart.
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@boundary.test', 'x', now(), now(), now()),
  ('bbbbbbbb-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@boundary.test', 'x', now(), now(), now());

-- A trigger on auth.users already created these rows, so this fills in the fields the
-- tests care about rather than inserting fresh.
insert into public.profiles (id, first_name, timezone) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Ada', 'Europe/London'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'Mel', 'Australia/Melbourne')
on conflict (id) do update set first_name = excluded.first_name, timezone = excluded.timezone;

insert into public.couples (id, partner_a_id, partner_b_id)
values ('cccccccc-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000002');

-- The couple's day is the later of the two local dates: at 15:00 UTC, Melbourne has already
-- rolled over to the 18th, so the couple is on the 18th even though London is still on the 17th.
select is(
  (select local_date from private.couple_day('cccccccc-0000-0000-0000-000000000003', '2026-08-17T15:00:00Z'::timestamptz)),
  '2026-08-18'::date,
  'couple day takes the later of the two partners local dates'
);

-- The boundary is `greatest()` of the two partners' next local midnights, which means the couple
-- effectively lives on the *ahead* partner's calendar: the day rolls over at Melbourne's midnight.
-- Worth being explicit that this is a real trade-off, not an oversight — any single shared day for
-- a couple nine hours apart has to break someone's midnight, and this pins which. Concretely, this
-- boundary (2026-08-18 14:00Z) is midnight in Melbourne but 3pm in London, so the London partner's
-- daily question resets mid-afternoon. Flipping to `least()` would just move the compromise onto
-- Melbourne instead.
select is(
  (select next_boundary from private.couple_day('cccccccc-0000-0000-0000-000000000003', '2026-08-17T15:00:00Z'::timestamptz)),
  private.next_local_midnight('Australia/Melbourne', '2026-08-17T15:00:00Z'::timestamptz),
  'couple boundary is the later of the two partners local midnights (the ahead partner''s)'
);

select ok(
  (select next_boundary from private.couple_day('cccccccc-0000-0000-0000-000000000003', '2026-08-17T15:00:00Z'::timestamptz))
    > '2026-08-17T15:00:00Z'::timestamptz,
  'couple boundary is still ahead of the given instant'
);

-- A profile with no timezone set must not break the couple's day — it falls back to UTC.
update public.profiles set timezone = null where id = 'bbbbbbbb-0000-0000-0000-000000000002';
select is(
  (select local_date from private.couple_day('cccccccc-0000-0000-0000-000000000003', '2026-08-17T15:00:00Z'::timestamptz)),
  '2026-08-17'::date,
  'a null timezone falls back to UTC instead of nulling out the couple day'
);

select * from finish();
rollback;
