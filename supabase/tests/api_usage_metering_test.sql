-- The rollup is the only thing in the metering schema with judgement in it, and every piece of that
-- judgement is about not being confidently wrong regarding money:
--
--   * An endpoint we have no price for must roll up to a NULL cost, never 0. Zero reads as "this
--     endpoint is free", which is the one conclusion that would stop anyone investigating it.
--
--   * A price change must not restate history. `api_rates` is versioned by `effective_from`
--     precisely so that last month keeps costing what it cost, and a rollup that always used the
--     current rate would quietly rewrite the past every time FlightAware changed a number.
--
--   * Re-running a day must restate it, not add to it. Late rows arrive and rates get corrected,
--     and the fix for both is "roll that day again" -- which is only a fix if it is idempotent.
--
--   * `distinct_upstream` must count distinct real-world flights, not calls. The gap between the
--     two IS the duplicate-fetch waste in `refresh-due-flights`'s main loop (which, unlike
--     `syncLivePositions`, does not dedupe by fa_flight_id), so a bug that collapsed them would
--     hide exactly the number this table was built to expose.
--
-- And one thing that is not about money: these tables authorise nothing, but they describe how much
-- every couple flies, so `authenticated` must not reach them at all.

begin;
select plan(18);

-- Real rates are seeded by 20261109000200 and would collide with the ones below. Cleared inside
-- this transaction (and so rolled back) because what is under test is the mechanism -- the cost
-- basis, the versioning, the idempotence -- and not the prices FlightAware happens to charge. A
-- test that broke every time a rate was added would be testing the invoice, not the code.
delete from private.api_rates;

-- ---------------------------------------------------------------------------
-- Two couples, one real-world flight, polled twice each -- the duplicate-fetch shape
-- ---------------------------------------------------------------------------

insert into private.api_usage_events
  (provider, endpoint, called_by, status, was_retry, fa_flight_id, served_flight_count, occurred_at)
values
  ('aeroapi', 'flights/{id}', 'refresh-due-flights', 200, false, 'QF9-abc', 1, date '2026-11-01' + interval '1 hour'),
  ('aeroapi', 'flights/{id}', 'refresh-due-flights', 200, false, 'QF9-abc', 1, date '2026-11-01' + interval '1 hour 1 minute'),
  ('aeroapi', 'flights/{id}', 'refresh-due-flights', 200, false, 'QF9-abc', 1, date '2026-11-01' + interval '2 hours'),
  ('aeroapi', 'flights/{id}', 'refresh-due-flights', 200, false, 'QF9-abc', 1, date '2026-11-01' + interval '2 hours 1 minute'),
  -- A different flight, one poll, plus a 429 and its retry.
  ('aeroapi', 'flights/{id}', 'refresh-due-flights', 200, false, 'NZ7-xyz', 1, date '2026-11-01' + interval '3 hours'),
  ('aeroapi', 'flights/{id}', 'refresh-due-flights', 429, false, 'NZ7-xyz', 1, date '2026-11-01' + interval '4 hours'),
  ('aeroapi', 'flights/{id}', 'refresh-due-flights', 200, true,  'NZ7-xyz', 1, date '2026-11-01' + interval '4 hours'),
  -- A different endpoint entirely, and one the rate table will never know about.
  ('aeroapi', 'airports/{id}/weather/observations', 'refresh-due-flights', 200, false, null, 1, date '2026-11-01' + interval '5 hours'),
  -- The next day, which must not leak into the first day's totals.
  ('aeroapi', 'flights/{id}', 'refresh-due-flights', 200, false, 'QF9-abc', 1, date '2026-11-02' + interval '1 hour');

insert into private.api_rates (provider, endpoint, unit_price_usd, effective_from, note) values
  ('aeroapi', 'flights/{id}', 0.005000, date '2026-01-01', 'test rate'),
  ('aeroapi', 'flights/{id}', 0.010000, date '2026-11-02', 'test rate, doubled');

select private.roll_up_api_usage(date '2026-11-01');

select is(
  (select calls from private.api_usage_daily
    where day = date '2026-11-01' and endpoint = 'flights/{id}'),
  7, 'every call that day is counted, including the failure and its retry'
);

select is(
  (select errors from private.api_usage_daily
    where day = date '2026-11-01' and endpoint = 'flights/{id}'),
  1, 'the 429 is the only error'
);

select is(
  (select retries from private.api_usage_daily
    where day = date '2026-11-01' and endpoint = 'flights/{id}'),
  1, 'the retry is counted as one'
);

-- 7 calls against 2 real-world flights. This ratio is the whole point of the table.
select is(
  (select distinct_upstream from private.api_usage_daily
    where day = date '2026-11-01' and endpoint = 'flights/{id}'),
  2, 'distinct_upstream counts real-world flights, not calls'
);

-- Six of the seven returned a 2xx. The 429 returned no page, so FlightAware did not bill it --
-- confirmed by the invoice that 20261109000200 is built on, where 345 calls produced 342 pages.
select is(
  (select billable_calls from private.api_usage_daily
    where day = date '2026-11-01' and endpoint = 'flights/{id}'),
  6, 'only the calls that returned a page are billable'
);

select is(
  (select estimated_cost_usd from private.api_usage_daily
    where day = date '2026-11-01' and endpoint = 'flights/{id}'),
  0.030000::numeric, 'and the cost is those six, not all seven'
);

-- ---------------------------------------------------------------------------
-- An unpriced endpoint is unknown, not free
-- ---------------------------------------------------------------------------

select ok(
  (select estimated_cost_usd from private.api_usage_daily
    where day = date '2026-11-01' and endpoint = 'airports/{id}/weather/observations') is null,
  'an endpoint with no rate rolls up to a null cost'
);

select is(
  (select calls from private.api_usage_daily
    where day = date '2026-11-01' and endpoint = 'airports/{id}/weather/observations'),
  1, 'and its calls are still counted'
);

-- ---------------------------------------------------------------------------
-- A rate change applies forward, not backward
-- ---------------------------------------------------------------------------

select private.roll_up_api_usage(date '2026-11-02');

select is(
  (select estimated_cost_usd from private.api_usage_daily
    where day = date '2026-11-02' and endpoint = 'flights/{id}'),
  0.010000::numeric, 'the second day uses the rate that took effect that day'
);

select is(
  (select estimated_cost_usd from private.api_usage_daily
    where day = date '2026-11-01' and endpoint = 'flights/{id}'),
  0.030000::numeric, 'and the first day is unchanged by the new rate'
);

-- ---------------------------------------------------------------------------
-- Re-running restates
-- ---------------------------------------------------------------------------

select private.roll_up_api_usage(date '2026-11-01');

select is(
  (select calls from private.api_usage_daily
    where day = date '2026-11-01' and endpoint = 'flights/{id}'),
  7, 'rolling the same day twice restates it rather than doubling it'
);

select is(
  (select count(*)::integer from private.api_usage_daily where day = date '2026-11-01'),
  2, 'and produces no duplicate rows'
);

-- A day of nothing but failures costs nothing -- but is still visible as calls, which is the
-- signal that something is wrong.
insert into private.api_usage_events (provider, endpoint, called_by, status, occurred_at)
values
  ('aeroapi', 'flights/{id}', 'refresh-due-flights', 500, date '2026-11-03' + interval '1 hour'),
  ('aeroapi', 'flights/{id}', 'refresh-due-flights', 404, date '2026-11-03' + interval '2 hours');

select private.roll_up_api_usage(date '2026-11-03');

select is(
  (select estimated_cost_usd from private.api_usage_daily
    where day = date '2026-11-03' and endpoint = 'flights/{id}'),
  0.000000::numeric, 'a day of failures costs nothing'
);

-- ---------------------------------------------------------------------------
-- Retention
-- ---------------------------------------------------------------------------

insert into private.api_usage_events (provider, endpoint, called_by, status, occurred_at)
values ('aeroapi', 'flights/{id}', 'refresh-due-flights', 200, now() - interval '90 days');

select is(
  private.purge_api_usage_events(60),
  1, 'the purge removes rows past the retention window'
);

select ok(
  not exists (
    select 1 from private.api_usage_events where occurred_at < now() - interval '60 days'
  ),
  'and leaves nothing older behind'
);

-- ---------------------------------------------------------------------------
-- Unreachable by a signed-in client
-- ---------------------------------------------------------------------------
--
-- `private` is not served over PostgREST at all (config.toml serves public and graphql_public), so
-- this is belt and braces -- but it is the same belt `flight_limit_overrides_test` wears, and for
-- the same reason: the protection is a config line somewhere else, and a test is what notices if
-- that line ever changes.

set local role authenticated;

select throws_ok(
  $$ select * from private.api_usage_events $$,
  '42501',
  NULL,
  'a signed-in client cannot read what anyone spends'
);

-- The writer is a security-definer function in `public`, which means PostgREST WILL serve it. The
-- only thing standing between a signed-in client and forged usage rows is the revoke, because a
-- new function grants EXECUTE to PUBLIC by default. That default is the bug this pins.
select throws_ok(
  $$ select public.record_api_call('aeroapi', 'flights/{id}', 'forged') $$,
  '42501',
  NULL,
  'a signed-in client cannot forge a usage row'
);

set local role postgres;

-- And the role that actually writes them can.
set local role service_role;
select lives_ok(
  $$ select public.record_api_call('aeroapi', 'flights/{id}', 'refresh-due-flights', 200) $$,
  'the service role can record a call'
);
set local role postgres;

select * from finish();
rollback;
