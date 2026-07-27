-- Flight stats (domestic/international/countries breakdown on the Passport "Flight Stats" page)
-- used to only work for flights linked to a Trip, because country was only ever known through a
-- trip's curated Place — a bare tracked Flight (the only way to add a flight now, see
-- 20260712-era "no self-reported flights" removal) never carried a country at all. Flights should
-- count for stats independently of trips, so country now lives directly on the flight row.
--
-- Backfilled from the `airports` reference table (already keyed by iata, already the single
-- source of truth the in-app airport search uses) rather than re-querying AeroAPI — instant, free,
-- and covers every existing flight whose origin/destination iata is a row in that table.
alter table public.flights
  add column origin_country text,
  add column destination_country text;

update public.flights f
set origin_country = a.country
from public.airports a
where a.iata = f.origin_iata
  and f.origin_country is null;

update public.flights f
set destination_country = a.country
from public.airports a
where a.iata = f.destination_iata
  and f.destination_country is null;
