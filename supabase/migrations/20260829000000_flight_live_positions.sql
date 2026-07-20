-- Shared, deduped live-position cache — one row per real-world flight (keyed by AeroAPI's own
-- fa_flight_id, not per-couple), populated from free ADS-B mirrors (adsb.lol/adsb.fi/
-- airplanes.live) instead of AeroAPI's paid /position endpoint. Two couples independently
-- tracking the same real flight share one cache row, so refresh-due-flights only ever fetches
-- a given flight's live position once per cron tick regardless of how many couples are watching
-- it — see _shared/adsb.ts and flight-sync.ts's syncLivePositionForFaFlightId.
--
-- Edge-Function-internal only: RLS is enabled with zero policies, so it's unreachable by the
-- anon/authenticated roles entirely (service_role, the only role Edge Functions use here,
-- bypasses RLS). The client never queries this table directly — it keeps consuming
-- flights.position_* the same way it always has; this table is purely the dedup layer behind
-- that write.

create table public.flight_live_positions (
  fa_flight_id text primary key,
  atc_ident text,
  hex text,
  -- Which candidate key produced the match, and which provider answered — recorded from day one
  -- so real-world mirror coverage/hit-rate against Twofold's actual routes can be measured after
  -- launch instead of guessed.
  query_key text,
  source text,
  latitude double precision,
  longitude double precision,
  altitude double precision,
  groundspeed double precision,
  heading double precision,
  consecutive_failures integer not null default 0,
  fetched_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint flight_live_positions_query_key_check check (
    query_key is null or query_key in ('atc_ident', 'icao_fallback', 'aeroapi_fallback')
  ),
  constraint flight_live_positions_source_check check (
    source is null or source in ('adsb.lol', 'adsb.fi', 'airplanes.live', 'aeroapi_fallback')
  )
);

alter table public.flight_live_positions enable row level security;
