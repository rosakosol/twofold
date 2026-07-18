-- Shared, deduped 60-day delay-performance cache — one row per flight *designator* (e.g. "UAE1"),
-- not per tracked instance or per couple, since on-time performance is a property of the
-- recurring flight number, not any single day's flight. Computed on-demand (when someone opens
-- that flight's detail screen), not proactively for every tracked flight, and cached for ~24h —
-- see _shared/flight-sync.ts's computeDelayStats, the only writer of this table.
--
-- Requires AeroAPI's Standard tier (historical data isn't available on Personal tier) — see
-- flight-delay-stats/index.ts's caller.
--
-- Edge-Function-internal only: RLS enabled, zero policies (service_role bypasses RLS). The client
-- never queries this table directly — it only ever sees the edge function's JSON response.

create table public.flight_delay_stats (
  ident text primary key,
  observed_count integer not null,
  late_percent numeric not null,
  average_late_minutes numeric not null,
  early_percent numeric not null,
  on_time_percent numeric not null,
  late_15_percent numeric not null,
  late_30_percent numeric not null,
  late_45_percent numeric not null,
  cancelled_percent numeric not null,
  diverted_percent numeric not null,
  computed_at timestamptz not null default now()
);

alter table public.flight_delay_stats enable row level security;
