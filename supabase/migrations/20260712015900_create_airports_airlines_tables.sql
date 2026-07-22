-- Schema-parity companion to 20260712020000_airports_airlines_public_read.sql. The
-- `airports`/`airlines` tables were created directly on the hosted project (out-of-band, not
-- via migration) and are populated separately from a large external reference dataset (~6k
-- airports, ~1.1k airlines) that's too large to check in as SQL here. This migration only
-- creates the empty schema — matching what already exists on the hosted project (`if not
-- exists`, so it's a no-op there) — so a fresh local `supabase start`/`db reset` has a table
-- for the public-read policy below to attach to, instead of erroring on a missing relation.

create table if not exists public.airports (
  iata text primary key,
  icao text,
  name text not null,
  city text,
  country text,
  latitude double precision not null,
  longitude double precision not null,
  timezone text
);

alter table public.airports enable row level security;

create table if not exists public.airlines (
  iata text primary key,
  icao text,
  name text not null
);

alter table public.airlines enable row level security;
