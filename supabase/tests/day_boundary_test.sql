-- Day-boundary helpers behind the daily question and streak reset.
--
-- These exist because streaks used to roll over at whatever wall-clock time the couple happened to
-- sign up — people were losing streaks at 9:45pm. The rule is now each partner's *own* local
-- midnight: a London/Melbourne couple genuinely has two different day boundaries, because nine
-- hours apart there is no shared midnight to find. An earlier attempt shared one boundary across
-- the couple (the later of the two), which just moved the arbitrary reset onto whichever partner
-- was behind — London's day ended at 3pm.

begin;
select plan(16);

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

-- Each partner now gets their own boundary — `private.viewer_day()` reports the caller's own
-- timezone, not a shared couple-wide one. At 15:00 UTC, Melbourne has rolled over to the 18th
-- while London is still on the 17th, and each of them should see exactly that. The old shared
-- `couple_day` (greatest of the two) put both on the 18th, which meant London's daily question
-- reset at 3pm local.
--
-- Run as postgres rather than `authenticated`: private.viewer_day is a private-schema helper that
-- app roles deliberately cannot reach (it's only ever called from security-definer public
-- functions). auth.uid() reads the JWT claim regardless of the current role, so setting the claim
-- alone is enough to impersonate each partner here.
select set_config('request.jwt.claim.sub', 'aaaaaaaa-0000-0000-0000-000000000001', true);
select is(
  (select local_date from private.viewer_day('2026-08-17T15:00:00Z'::timestamptz)),
  '2026-08-17'::date,
  'London partner is on their own local date'
);
select is(
  (select next_boundary from private.viewer_day('2026-08-17T15:00:00Z'::timestamptz)),
  private.next_local_midnight('Europe/London', '2026-08-17T15:00:00Z'::timestamptz),
  'London partner rolls over at London midnight'
);

select set_config('request.jwt.claim.sub', 'bbbbbbbb-0000-0000-0000-000000000002', true);
select is(
  (select local_date from private.viewer_day('2026-08-17T15:00:00Z'::timestamptz)),
  '2026-08-18'::date,
  'Melbourne partner is on their own local date, a day ahead'
);
select is(
  (select next_boundary from private.viewer_day('2026-08-17T15:00:00Z'::timestamptz)),
  private.next_local_midnight('Australia/Melbourne', '2026-08-17T15:00:00Z'::timestamptz),
  'Melbourne partner rolls over at Melbourne midnight'
);

-- The two boundaries genuinely differ — this is the whole point of the change.
select isnt(
  (select next_boundary from private.viewer_day('2026-08-17T15:00:00Z'::timestamptz)),
  private.next_local_midnight('Europe/London', '2026-08-17T15:00:00Z'::timestamptz),
  'the two partners do not share a boundary'
);

-- Both still resolve to the same couple, so they answer the same shared daily session.
select is(
  (select couple_id from private.viewer_day('2026-08-17T15:00:00Z'::timestamptz)),
  'cccccccc-0000-0000-0000-000000000003'::uuid,
  'a per-partner boundary still resolves the shared couple'
);

-- A profile with no timezone set falls back to UTC rather than reporting no day at all.
update public.profiles set timezone = null where id = 'bbbbbbbb-0000-0000-0000-000000000002';
select set_config('request.jwt.claim.sub', 'bbbbbbbb-0000-0000-0000-000000000002', true);
select is(
  (select local_date from private.viewer_day('2026-08-17T15:00:00Z'::timestamptz)),
  '2026-08-17'::date,
  'a null timezone falls back to UTC instead of nulling out the day'
);

select * from finish();
rollback;
