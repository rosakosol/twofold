-- ---------------------------------------------------------------------------
-- What we spend at AeroAPI, and on what
-- ---------------------------------------------------------------------------
--
-- `refresh-due-flights` already carries a cadence tuned against cost: its own header records that
-- the mid-cruise tier "was 2 min -- cost data showed this tier alone was responsible for most of
-- the /flights/{ident} bill (291 calls/$1.46 in 24h)". That number came from FlightAware's
-- dashboard, read by hand, after something prompted someone to go and look. Nothing in this
-- database has ever recorded an outbound API call.
--
-- This is the record. Every metered third-party call lands here, and the console reads the
-- rollup rather than the raw rows.
--
-- ---------------------------------------------------------------------------
-- Why `private`
-- ---------------------------------------------------------------------------
--
-- Same reasoning as `private.flight_limit_overrides`: `config.toml` serves `public` and
-- `graphql_public` only, so a table here is unreachable over PostgREST entirely -- no grant to get
-- wrong and no policy to get subtly wrong. The console reaches it through security-definer
-- functions gated on `is_billing_admin()`, which is the only door.
--
-- ---------------------------------------------------------------------------
-- Provider-agnostic on purpose
-- ---------------------------------------------------------------------------
--
-- AeroAPI is the only metered dependency today -- the ADS-B mirrors in `_shared/adsb.ts` and
-- `_shared/adsbdb.ts` are deliberately free, and R2 egress is the only other thing that could
-- start costing. `provider` is a column rather than this being an `aeroapi_calls` table, because
-- the second metered API always arrives and it should not need a second schema.

create table if not exists private.api_usage_events (
  id bigint generated always as identity primary key,

  -- 'aeroapi'. Lowercase, no enum: a check constraint would have to be migrated every time a
  -- provider is added, and this table is written by application code that already knows the name.
  provider text not null,

  -- The BILLABLE CLASS, never the raw path. `/flights/UA123` and `/flights/QF9` are the same
  -- priced thing, and storing raw paths gives unbounded cardinality and a column you cannot group
  -- by -- which is the one thing this table exists to do. Callers pass e.g. 'flights/{ident}',
  -- 'flights/{id}', 'schedules', 'flights/search', 'airports/{id}/weather/observations'.
  endpoint text not null,

  -- Which edge function made the call, e.g. 'refresh-due-flights'. This is what turns "we spent
  -- $40" into "the cron did, not the app", and it is the difference between a cadence bug and a
  -- user-facing one.
  called_by text not null,

  -- HTTP status, or null when the request never got one (network failure, timeout). A run of 429s
  -- is both a cost signal and a reliability signal, so failures are recorded, not dropped.
  status integer,

  -- `aeroRequest` retries once on 429/5xx. The retry is a separate billable call and gets its own
  -- row, flagged -- otherwise a provider having a bad afternoon looks like us making more calls.
  was_retry boolean not null default false,

  duration_ms integer,

  -- ---------------------------------------------------------------------------
  -- Attribution
  -- ---------------------------------------------------------------------------
  --
  -- No foreign keys, for the same reason `subscription_events` has none: the usage record has to
  -- outlive the flight and the couple it describes. A cascade would erase exactly the row someone
  -- later needs to explain a bill, and a bill is not retracted when an account is deleted.

  -- The upstream flight this call was about. The key measurement, not decoration: the main loop in
  -- `refresh-due-flights` is NOT deduped by fa_flight_id (only `syncLivePositions` is, and that
  -- pass hits the free ADS-B mirrors), so two couples tracking the same real-world flight bill two
  -- identical calls per tick. Counting rows against distinct (fa_flight_id, minute) measures that
  -- waste directly, and is what a decision to fix it should rest on.
  fa_flight_id text,

  flight_id uuid,
  couple_id uuid,

  -- How many `flights` rows this one call served. 1 today, because nothing is deduped. If the main
  -- loop is taught to fetch once and apply to N rows, this becomes N -- one call, honestly
  -- recorded once, rather than N fabricated rows that would make the fix look like it changed
  -- nothing.
  served_flight_count integer not null default 1 check (served_flight_count >= 1),

  occurred_at timestamptz not null default now()
);

comment on table private.api_usage_events is
  'One row per outbound metered third-party call. In `private` because it is unreachable over '
  'PostgREST there; the console reads it through is_billing_admin()-gated functions. Raw rows are '
  'kept 60 days and rolled into api_usage_daily nightly.';

-- The rollup's daily scan, and the retention delete.
create index if not exists api_usage_events_occurred_idx
  on private.api_usage_events (occurred_at);

-- "What did this endpoint cost over this window" -- the console's main read.
create index if not exists api_usage_events_provider_endpoint_idx
  on private.api_usage_events (provider, endpoint, occurred_at);

-- The duplicate-fetch measurement. Partial because the overwhelming majority of rows will carry an
-- fa_flight_id and the ones that do not (weather, airport lookups) are never part of this query.
create index if not exists api_usage_events_upstream_idx
  on private.api_usage_events (fa_flight_id, occurred_at)
  where fa_flight_id is not null;

-- ---------------------------------------------------------------------------
-- Prices live in a table, not in code
-- ---------------------------------------------------------------------------
--
-- Cost is a join, not a constant. FlightAware changes its rates and that becomes a row, not a
-- deploy -- and historical months keep costing what they actually cost rather than being silently
-- restated by the current price.
--
-- Deliberately seeded EMPTY. A plausible-looking guess at AeroAPI's per-endpoint pricing would
-- produce a dashboard that reads as authoritative and is quietly wrong about money, which is worse
-- than one that says it does not know yet. Fill this in from a real FlightAware invoice; until
-- then the rollup records call counts and a null cost, and the console says so.

create table if not exists private.api_rates (
  provider text not null,
  endpoint text not null,
  unit_price_usd numeric(12, 6) not null check (unit_price_usd >= 0),
  -- Inclusive. The rate in force for a given day is the latest row at or before it.
  effective_from date not null,
  note text,
  primary key (provider, endpoint, effective_from)
);

comment on table private.api_rates is
  'Unit price per billable endpoint class, versioned by effective_from. Seeded empty on purpose: '
  'guessed prices produce a dashboard that is confidently wrong about money. Populate from a real '
  'invoice.';

-- The rate in force for a provider/endpoint on a given day, or null if we have never been told.
create or replace function private.api_rate_on(p_provider text, p_endpoint text, p_day date)
returns numeric
language sql
stable
set search_path = private, public
as $$
  select unit_price_usd
  from private.api_rates
  where provider = p_provider
    and endpoint = p_endpoint
    and effective_from <= p_day
  order by effective_from desc
  limit 1;
$$;

-- ---------------------------------------------------------------------------
-- The rollup
-- ---------------------------------------------------------------------------
--
-- Built with the table rather than after it. A rollup added once the events table is already large
-- has to be backfilled from data that retention has by then deleted, so the aggregate history
-- simply starts wherever someone got round to it.

create table if not exists private.api_usage_daily (
  day date not null,
  provider text not null,
  endpoint text not null,
  calls integer not null,
  -- Non-2xx plus the calls that never got a status at all.
  errors integer not null,
  retries integer not null,
  -- Distinct upstream flights touched that day. `calls` far exceeding this is the duplicate-fetch
  -- waste made visible.
  distinct_upstream integer,
  served_flights integer not null,
  -- Null when `api_rates` has no rate for this endpoint on this day. Null means "not known",
  -- never zero -- a missing price must not read as a free call.
  estimated_cost_usd numeric(14, 6),
  rolled_up_at timestamptz not null default now(),
  primary key (day, provider, endpoint)
);

comment on table private.api_usage_daily is
  'Per-day rollup of api_usage_events, kept indefinitely. estimated_cost_usd is null where no rate '
  'is known -- an unknown price is not a free call.';

-- Recomputes one day from the raw events. Idempotent: re-running restates the day rather than
-- adding to it, so a late-arriving row or a corrected rate can be picked up by simply running it
-- again for that date.
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
    day, provider, endpoint, calls, errors, retries, distinct_upstream, served_flights,
    estimated_cost_usd, rolled_up_at
  )
  select
    p_day,
    e.provider,
    e.endpoint,
    count(*)::integer,
    count(*) filter (where e.status is null or e.status < 200 or e.status >= 300)::integer,
    count(*) filter (where e.was_retry)::integer,
    count(distinct e.fa_flight_id)::integer,
    coalesce(sum(e.served_flight_count), 0)::integer,
    -- Every call counts toward the bill, including the failed ones: a 500 from AeroAPI is still a
    -- request we made. Whether their invoice agrees is exactly what the reconciliation field on
    -- the console is for.
    count(*) * private.api_rate_on(e.provider, e.endpoint, p_day),
    now()
  from private.api_usage_events e
  where e.occurred_at >= p_day::timestamptz
    and e.occurred_at < (p_day + 1)::timestamptz
  group by e.provider, e.endpoint
  on conflict (day, provider, endpoint) do update set
    calls = excluded.calls,
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

-- 60 days of raw rows. Long enough to investigate a bill after it arrives and to re-roll a month
-- if a rate turns out to have been wrong; short enough that a per-call table on a growing flight
-- load does not become the largest thing in the database.
create or replace function private.purge_api_usage_events(p_keep_days integer default 60)
returns integer
language plpgsql
security definer
set search_path = private, public
as $$
declare
  v_rows integer;
begin
  delete from private.api_usage_events
  where occurred_at < now() - make_interval(days => p_keep_days);
  get diagnostics v_rows = row_count;
  return v_rows;
end;
$$;

-- ---------------------------------------------------------------------------
-- The one door into a schema nothing can reach
-- ---------------------------------------------------------------------------
--
-- `private` is not in `config.toml`'s `schemas`, which is the whole reason the tables above are
-- safe -- and also means supabase-js cannot insert into them. An edge function holding the service
-- role key still talks to PostgREST, and PostgREST does not serve this schema at any privilege
-- level. So the writer needs a function in `public` that runs as its owner.
--
-- Execute is revoked from everyone and granted back to `service_role` alone. The default on a new
-- function is EXECUTE to PUBLIC, so without the revoke below any signed-in client could forge
-- usage rows -- which would not cost money, but would corrupt the one record used to decide where
-- the money goes, and a metering table that can be written by the thing being metered is worth
-- nothing.
create or replace function public.record_api_call(
  p_provider text,
  p_endpoint text,
  p_called_by text,
  p_status integer default null,
  p_was_retry boolean default false,
  p_duration_ms integer default null,
  p_fa_flight_id text default null,
  p_flight_id uuid default null,
  p_couple_id uuid default null,
  p_served_flight_count integer default 1
)
returns void
language sql
security definer
set search_path = private, public
as $$
  insert into private.api_usage_events (
    provider, endpoint, called_by, status, was_retry, duration_ms,
    fa_flight_id, flight_id, couple_id, served_flight_count
  )
  values (
    p_provider, p_endpoint, p_called_by, p_status, p_was_retry, p_duration_ms,
    p_fa_flight_id, p_flight_id, p_couple_id, greatest(coalesce(p_served_flight_count, 1), 1)
  );
$$;

revoke execute on function public.record_api_call(
  text, text, text, integer, boolean, integer, text, uuid, uuid, integer
) from public, anon, authenticated;

grant execute on function public.record_api_call(
  text, text, text, integer, boolean, integer, text, uuid, uuid, integer
) to service_role;
