-- ---------------------------------------------------------------------------
-- Real AeroAPI prices, and the billing unit they are charged in
-- ---------------------------------------------------------------------------
--
-- 20261109000100 seeded `api_rates` empty on purpose, because a guessed price produces a dashboard
-- that reads as authoritative and is quietly wrong about money. A FlightAware invoice has since
-- arrived. These are its numbers, and they divide exactly:
--
--   Function                                Calls  Pages    Cost   per page
--   GET /airports/{id}                         20     20   $0.30   $0.015
--   GET /airports/{id}/weather/observations    50     50   $0.10   $0.002
--   GET /flights/{ident}                      345    342   $1.71   $0.005
--   GET /history/flights/{ident}              115    115   $2.30   $0.020
--   GET /schedules/{date_start}/{date_end}     26     26   $0.52   $0.020
--                                             556    553   $4.93
--
-- ---------------------------------------------------------------------------
-- The rollup was charging for the wrong thing
-- ---------------------------------------------------------------------------
--
-- Note the third row: 345 calls but 342 pages, and $1.71 is 342 x $0.005, not 345 x $0.005.
-- FlightAware bills per page returned, not per request made. Three of those requests produced no
-- page and cost nothing.
--
-- `roll_up_api_usage` multiplied `count(*)` by the rate, on the reasoning -- written into its own
-- comment -- that "a 500 from AeroAPI is still a request we made". The invoice says otherwise, so
-- that is corrected here rather than left to be discovered as a permanent 1% overstatement.
--
-- The cost basis becomes calls that returned a 2xx. That is an inference: the invoice shows the
-- gap but not which three requests made it, and 404 -- which `aeroRequest` deliberately treats as
-- "not found" rather than an error -- is the obvious candidate, along with the 429s and 5xxs that
-- trigger its retry. Every one of those returns no page. The inference is recorded here so that
-- the next invoice either confirms it or shows a gap worth chasing, which is what the console's
-- reconciliation field is for.
--
-- `calls` is still recorded in full. Total attempts and billable pages are different questions --
-- a run of unbillable calls costs nothing and still means something is wrong.
--
-- ---------------------------------------------------------------------------
-- What this does NOT model: the discount
-- ---------------------------------------------------------------------------
--
-- The same invoice reads "Total $4.93, Discounted Total $0.41" -- 8.3% of list. Every figure here
-- is LIST price, which is the only one that can be derived from a call count, and it reconciles to
-- the invoice's own total exactly.
--
-- What produces the other number is not visible from this side: it could be a plan allowance, a
-- volume tier or a promotional rate, and each would behave differently as usage grows. Guessing
-- would put the budget alert off by a factor of twelve in whichever direction the guess was wrong.
-- So: list price here, and the discount is left to be understood before the alert threshold is set
-- against it.

alter table private.api_usage_daily
  add column if not exists billable_calls integer;

comment on column private.api_usage_daily.billable_calls is
  'Calls that returned a 2xx, and so returned a page. This is the cost basis -- FlightAware bills '
  'per page returned, not per request made. Differs from `calls` by the requests that produced '
  'nothing: 404s, and the 429/5xx responses that trigger aeroRequest''s retry.';

comment on column private.api_usage_daily.estimated_cost_usd is
  'LIST cost: billable_calls x the rate in force that day. Reconciles exactly to the invoice''s '
  '"Total". The invoice''s "Discounted Total" is not modelled -- see 20261109000200.';

create or replace function private.roll_up_api_usage(p_day date default (current_date - 1))
returns integer
language plpgsql
security definer
set search_path = private, public
as $$
declare
  v_rows integer;
begin
  insert into private.api_usage_daily (
    day, provider, endpoint, calls, billable_calls, errors, retries, distinct_upstream,
    served_flights, estimated_cost_usd, rolled_up_at
  )
  select
    p_day,
    e.provider,
    e.endpoint,
    count(*)::integer,
    count(*) filter (where e.status between 200 and 299)::integer,
    count(*) filter (where e.status is null or e.status < 200 or e.status >= 300)::integer,
    count(*) filter (where e.was_retry)::integer,
    count(distinct e.fa_flight_id)::integer,
    coalesce(sum(e.served_flight_count), 0)::integer,
    -- Only the calls that returned a page. See this migration's header for why that is not
    -- `count(*)`, and for the three-call gap in the invoice that proves it.
    count(*) filter (where e.status between 200 and 299)
      * private.api_rate_on(e.provider, e.endpoint, p_day),
    now()
  from private.api_usage_events e
  where e.occurred_at >= p_day::timestamptz
    and e.occurred_at < (p_day + 1)::timestamptz
  group by e.provider, e.endpoint
  on conflict (day, provider, endpoint) do update set
    calls = excluded.calls,
    billable_calls = excluded.billable_calls,
    errors = excluded.errors,
    retries = excluded.retries,
    distinct_upstream = excluded.distinct_upstream,
    served_flights = excluded.served_flights,
    estimated_cost_usd = excluded.estimated_cost_usd,
    rolled_up_at = excluded.rolled_up_at;

  get diagnostics v_rows = row_count;
  return v_rows;
end;
$$;

-- ---------------------------------------------------------------------------
-- The rates
-- ---------------------------------------------------------------------------
--
-- `effective_from` is deliberately early rather than today's date: these are the prices the
-- invoice was already charging, so dating them from the first metered call means the first rollups
-- are costed correctly rather than reading as "price unknown" for their first day.
--
-- `flights/{id}` and `flights/{ident}` are one line on the invoice -- FlightAware reports both
-- under GET /flights/{ident}, since they are the same endpoint distinguished only by an
-- `ident_type` parameter. They are metered separately here because they answer different
-- questions (the cron polling a known flight, versus a person resolving one), and both carry the
-- same price, so the split costs nothing and reconciles to the same total.

insert into private.api_rates (provider, endpoint, unit_price_usd, effective_from, note) values
  ('aeroapi', 'flights/{ident}',                      0.005000, date '2026-01-01',
    'Invoice: 342 pages / $1.71. Reported with flights/{id} as one line.'),
  ('aeroapi', 'flights/{id}',                         0.005000, date '2026-01-01',
    'Same endpoint and price as flights/{ident}; split here to separate cron polling from lookups.'),
  ('aeroapi', 'history/flights/{ident}',              0.020000, date '2026-01-01',
    'Invoice: 115 pages / $2.30. Each paginated page is its own billed request.'),
  ('aeroapi', 'schedules',                            0.020000, date '2026-01-01',
    'Invoice: 26 pages / $0.52.'),
  ('aeroapi', 'airports/{id}',                        0.015000, date '2026-01-01',
    'Invoice: 20 pages / $0.30. The dearest per call of anything we routinely hit.'),
  ('aeroapi', 'airports/{id}/weather/observations',   0.002000, date '2026-01-01',
    'Invoice: 50 pages / $0.10.'),
  -- INFERRED, not invoiced. The forecast endpoint is only reached when observations fails
  -- (see fetchAirportWeather), which evidently did not happen in the invoiced period. Priced as
  -- its sibling so a fallback that starts firing shows a cost rather than a blank; the note is
  -- here so the number is never mistaken for one FlightAware confirmed.
  ('aeroapi', 'airports/{id}/weather/forecast',       0.002000, date '2026-01-01',
    'INFERRED from weather/observations, not seen on an invoice. Correct when one shows it.')
on conflict (provider, endpoint, effective_from) do update set
  unit_price_usd = excluded.unit_price_usd,
  note = excluded.note;

-- `flights/search` is deliberately absent. `searchRoute` exists but does not appear on the
-- invoice, so its price is genuinely unknown -- and an unknown price must roll up as null rather
-- than as a guess, which is the rule this table was built around.
