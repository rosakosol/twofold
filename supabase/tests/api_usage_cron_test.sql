-- Three things, and the first is the one that would go unnoticed longest.
--
--   * The seeded rates must reproduce the invoice they came from. A rate table that is nearly
--     right produces a dashboard that is plausibly wrong, which is worse than one that is
--     obviously wrong, because nobody goes looking. Feeding FlightAware's own page counts back
--     through `api_rate_on` and getting their own total back is the only check that actually
--     proves the numbers were transcribed correctly.
--
--   * The rollup must cover today as well as yesterday. A nightly-only pass leaves the console a
--     day stale, which is most of the way to useless: the 2-minute cruise tier that
--     `refresh-due-flights` was eventually caught spending on would have been just as invisible on
--     a dashboard that only ever showed yesterday.
--
--   * Neither rollup nor purge may be callable by a client. They are cron's, and `private` already
--     puts them out of PostgREST's reach -- but that reach is decided by a line in config.toml,
--     and an explicit revoke is what survives that line changing.

begin;
select plan(9);

-- ---------------------------------------------------------------------------
-- The seeded rates reproduce the invoice
-- ---------------------------------------------------------------------------
--
-- Page counts and totals from the FlightAware invoice quoted in 20261109000200:
--
--   GET /airports/{id}                         20 pages   $0.30
--   GET /airports/{id}/weather/observations    50 pages   $0.10
--   GET /flights/{ident}                      342 pages   $1.71
--   GET /history/flights/{ident}              115 pages   $2.30
--   GET /schedules/{date_start}/{date_end}     26 pages   $0.52
--                                                         -----
--                                                         $4.93
--
-- Every row is a 2xx, because a page returned is what the invoice counts.

insert into private.api_usage_events (provider, endpoint, called_by, status, occurred_at)
select 'aeroapi', e.endpoint, 'invoice-replay', 200, date '2026-10-01' + interval '1 hour'
from (values
  ('airports/{id}', 20),
  ('airports/{id}/weather/observations', 50),
  ('flights/{ident}', 342),
  ('history/flights/{ident}', 115),
  ('schedules', 26)
) as e(endpoint, pages),
lateral generate_series(1, e.pages);

select private.roll_up_api_usage(date '2026-10-01');

select is(
  (select sum(estimated_cost_usd) from private.api_usage_daily where day = date '2026-10-01'),
  4.930000::numeric, 'the seeded rates reproduce the invoice total exactly'
);

select is(
  (select estimated_cost_usd from private.api_usage_daily
    where day = date '2026-10-01' and endpoint = 'history/flights/{ident}'),
  2.300000::numeric, 'and each line of it -- history, the dearest of them'
);

select is(
  (select estimated_cost_usd from private.api_usage_daily
    where day = date '2026-10-01' and endpoint = 'flights/{ident}'),
  1.710000::numeric, 'and the one whose page count differs from its call count'
);

-- The split this codebase makes and the invoice does not: both cost the same, so a call recorded
-- either way reconciles to the same money.
select is(
  private.api_rate_on('aeroapi', 'flights/{id}', current_date),
  private.api_rate_on('aeroapi', 'flights/{ident}', current_date),
  'flights/{id} and flights/{ident} carry the same price'
);

-- `searchRoute` exists but never appeared on an invoice, so its price is genuinely unknown and
-- must stay that way rather than being quietly assumed.
select ok(
  private.api_rate_on('aeroapi', 'flights/search', current_date) is null,
  'an endpoint no invoice has shown has no price'
);

-- ---------------------------------------------------------------------------
-- The hourly pass covers both days that can still change
-- ---------------------------------------------------------------------------

insert into private.api_usage_events (provider, endpoint, called_by, status, occurred_at) values
  ('aeroapi', 'flights/{id}', 'refresh-due-flights', 200, now()),
  ('aeroapi', 'flights/{id}', 'refresh-due-flights', 200, now() - interval '1 day');

select private.roll_up_recent_api_usage();

select ok(
  exists (select 1 from private.api_usage_daily where day = current_date),
  'the hourly pass rolls up today, so the console is not a day behind'
);

select ok(
  exists (select 1 from private.api_usage_daily where day = current_date - 1),
  'and yesterday, so a row committed either side of midnight is not lost'
);

-- ---------------------------------------------------------------------------
-- Cron's, and nobody else's
-- ---------------------------------------------------------------------------

set local role authenticated;

select throws_ok(
  $$ select private.roll_up_recent_api_usage() $$,
  '42501',
  NULL,
  'a signed-in client cannot run the rollup'
);

select throws_ok(
  $$ select private.purge_api_usage_events() $$,
  '42501',
  NULL,
  'nor throw away the raw usage rows'
);

set local role postgres;

select * from finish();
rollback;
