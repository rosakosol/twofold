-- ---------------------------------------------------------------------------
-- flights: fill in the airport timezones that /schedules never provided
-- ---------------------------------------------------------------------------
--
-- A flight resolved from AeroAPI's /schedules endpoint arrives with no airport timezone on either
-- end: that endpoint returns flat origin/destination codes with no nested airport object, so
-- resolve-flight maps them with `timezone: null`. And /schedules is the ONLY source for anything
-- beyond AeroAPI's ~2-day live window, so every flight booked more than two days ahead — which is
-- most of them — was stored with no timezone at all.
--
-- The instant was always right. What was missing was the zone to render it in, and the app falls
-- back to the device's own timezone, so a UA60 leaving SFO at 23:20 local showed as 8:20am on a
-- phone set to UTC+2. It also made the app appear to contradict itself: the journey summary renders
-- in the user's home city and the detail cards render in the airport's, so with the airport's
-- missing, the two fell back to different places and disagreed.
--
-- add-flight fills this in going forward, from the same `airports` table this backfill uses. This
-- is for the rows that already exist, since nothing else would ever revisit them: the poller
-- rewrites live-tracking fields from AeroAPI, and AeroAPI's live rows are exactly the ones that
-- already had a timezone.
--
-- Only fills NULLs. A value AeroAPI supplied is left alone — it is the live source and would know
-- about an airport that has changed zone, where our reference table is a snapshot.
--
-- Matches on IATA first and ICAO second, the same precedence add-flight uses, because `airports` is
-- keyed on IATA and only some rows carry an ICAO.

update public.flights f
set origin_timezone = a.timezone
from public.airports a
where f.origin_timezone is null
  and a.timezone is not null
  and (a.iata = f.origin_iata or a.icao = f.origin_icao);

update public.flights f
set destination_timezone = a.timezone
from public.airports a
where f.destination_timezone is null
  and a.timezone is not null
  and (a.iata = f.destination_iata or a.icao = f.destination_icao);
