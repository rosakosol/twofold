-- The $100 monthly minimum is the fact that decides what this schema is for, so it is the fact
-- most worth pinning.
--
-- Below the floor, what we pay does not move. Call counts can double and the invoice is identical,
-- which means every number the console shows in dollars is a constant and the only figure that
-- actually moves is utilisation of the floor. Get that the wrong way round and the dashboard
-- reports a flat line as good news while the thing it was built to catch — a cadence constant
-- quietly tripling call volume, as the 2-minute cruise tier did — happens underneath it for free.
--
-- And the discount must stay observed. FlightAware applies volume discounts and publishes no
-- curve; a ratio inferred from our own invoices is knowledge, a ratio assumed is a number that
-- will be wrong in a direction nobody can reason about at exactly the moment it starts mattering.

begin;
select plan(11);

-- Deterministic months, well clear of current_date, so nothing here depends on the day it runs.
-- `api_usage_daily` is written directly rather than through the rollup: what is under test is the
-- month-to-date arithmetic, and going via the rollup would couple this to the rate table too.
insert into private.api_usage_daily (day, provider, endpoint, calls, billable_calls, errors, retries, served_flights, estimated_cost_usd) values
  (date '2026-03-01', 'aeroapi', 'flights/{id}', 100, 100, 0, 0, 100, 20.000000),
  (date '2026-03-15', 'aeroapi', 'flights/{id}', 100, 90,  10, 0, 100, 18.000000),
  (date '2026-03-31', 'aeroapi', 'schedules',     50,  50, 0, 0,  50, 12.000000),
  -- A different month, which must not leak in.
  (date '2026-04-02', 'aeroapi', 'flights/{id}', 999, 999, 0, 0, 999, 99.000000);

-- ---------------------------------------------------------------------------
-- The floor
-- ---------------------------------------------------------------------------

select is(
  private.api_minimum_on('aeroapi', date '2026-03-15'),
  100.00::numeric, 'the AeroAPI commitment is $100 a month'
);

select ok(
  private.api_minimum_on('nobody', date '2026-03-15') is null,
  'a provider with no commitment has no floor'
);

-- ---------------------------------------------------------------------------
-- Month to date
-- ---------------------------------------------------------------------------

select is(
  (select list_cost_usd from private.api_month_to_date('aeroapi', date '2026-03-01')),
  50.000000::numeric, 'the month sums its own days and not the next month''s'
);

select is(
  (select calls from private.api_month_to_date('aeroapi', date '2026-03-01')),
  250::bigint, 'total attempts across the month'
);

select is(
  (select billable_calls from private.api_month_to_date('aeroapi', date '2026-03-01')),
  240::bigint, 'and the billable subset, which is what the cost is built on'
);

-- $50 of list against a $100 floor. Half the commitment used — and, crucially, the same $100 paid
-- as if it were $5 or $95.
select is(
  (select list_utilisation_percent from private.api_month_to_date('aeroapi', date '2026-03-01')),
  50.00::numeric, 'utilisation is list cost against the floor, not spend'
);

-- ---------------------------------------------------------------------------
-- Projection
-- ---------------------------------------------------------------------------

-- March 2026 is entirely in the past, so every day is complete and the projection is just the
-- total. A projection that drifted from actual on a finished month would be an arithmetic bug
-- hiding in plain sight.
select is(
  (select projected_list_usd from private.api_month_to_date('aeroapi', date '2026-03-01')),
  50.000000::numeric, 'a completed month projects to exactly what it cost'
);

-- A month that has not started has no completed day to extrapolate from. Null, not zero: zero
-- would read as "we project spending nothing", which is a claim, and there is nothing to claim.
select ok(
  (select projected_list_usd from private.api_month_to_date('aeroapi', date '2099-01-01')) is null,
  'a month with no completed days projects nothing rather than zero'
);

-- ---------------------------------------------------------------------------
-- The discount, observed
-- ---------------------------------------------------------------------------

select ok(
  (select observed_discount_ratio from private.api_month_to_date('aeroapi', date '2026-03-01')) is null,
  'with no invoice recorded, the discount is unknown rather than assumed'
);

-- $4.15 charged against the $50 of list this database computed for the same month.
insert into private.api_invoices (provider, billing_month, list_total_usd, charged_usd, note)
values ('aeroapi', date '2026-03-01', 50.00, 4.15, 'test invoice');

select is(
  (select observed_discount_ratio from private.api_month_to_date('aeroapi', date '2026-03-01')),
  0.083000::numeric, 'once an invoice exists the ratio is measured from it'
);

-- ---------------------------------------------------------------------------
-- Not a client's business
-- ---------------------------------------------------------------------------

set local role authenticated;

select throws_ok(
  $$ select * from private.api_month_to_date() $$,
  '42501',
  NULL,
  'a signed-in client cannot read what the app costs to run'
);

set local role postgres;

select * from finish();
rollback;
