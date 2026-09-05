-- ---------------------------------------------------------------------------
-- places: constrain the values, since anyone signed in can write the rows
-- ---------------------------------------------------------------------------
--
-- `places_insert_authenticated` is `with check (true)` — every signed-in user can insert any row.
-- That is not a mistake to be reverted: `findOrCreatePlaceID` (BackendService.swift:419-448) is a
-- find-or-create against the `(city, country)` unique constraint, so the client genuinely has to be
-- able to insert a city the table has not seen. Locking inserts down would mean seeding every city
-- on earth, or routing them through an RPC for no gain — the row is not sensitive, it is reference
-- data.
--
-- What was missing is any statement about what a *valid* row looks like. Two things follow from
-- that, and only the second one really matters:
--
--   1. Growth. Bounded already, but only loosely: the unique constraint stops duplicate
--      (city, country) pairs, so filling the table means inventing distinct pairs rather than
--      repeating one. The length caps below make each row small; a per-user insert rate limit
--      (see `consume_rate_limit`, 20260918000000) is the tool if this ever needs a hard ceiling,
--      and is deliberately not applied here because legitimate inserts are rare and bursty —
--      onboarding sets a home city, a trip sets a destination.
--
--   2. Coordinates. `latitude`/`longitude` were plain `double precision` with no range check at
--      all, and they are not decoration: `Geo.distance` and the Home globe are computed from them,
--      and a place is shared couple data. A partner setting a home city at latitude 9999 does not
--      corrupt their own screen, it corrupts *both* — the distance card, the globe, the
--      "% of the way around the earth" line, and `update_couple_max_distance`'s persisted running
--      maximum, which is the one that does not heal when the bad row is fixed.
--
-- `not valid` on the check constraints: existing rows are not re-validated, so this cannot fail on
-- deploy against production data that predates it. New and updated rows are checked from now on.
-- If the existing rows are known good, a later `validate constraint` promotes them; nothing here
-- depends on that having happened.

alter table public.places
  add constraint places_latitude_range check (latitude >= -90 and latitude <= 90) not valid;

alter table public.places
  add constraint places_longitude_range check (longitude >= -180 and longitude <= 180) not valid;

-- Lengths, not formats. A city name can be almost anything (`Llanfairpwllgwyngyll…` is 58
-- characters, transliterations run longer), so these are set well above any real name rather than
-- attempting to describe one — the job is to stop a megabyte being stored in a text column, not to
-- adjudicate what counts as a place name.
alter table public.places
  add constraint places_city_length check (length(city) between 1 and 200) not valid;

alter table public.places
  add constraint places_country_length check (length(country) between 1 and 200) not valid;

-- IATA codes are exactly three letters. This one *can* be described precisely, so it is — and it
-- allows null, which is the common case: most places are cities rather than airports.
alter table public.places
  add constraint places_iata_code_format check (iata_code is null or iata_code ~ '^[A-Za-z]{3}$') not valid;

-- Timezone is an IANA identifier ("Australia/Melbourne"). Checked as a length bound rather than
-- against `pg_timezone_names`: that view is a runtime catalogue that changes with the tzdata the
-- server was built against, so validating against it would make a row's acceptability depend on
-- the database's patch level.
alter table public.places
  add constraint places_timezone_length check (timezone is null or length(timezone) between 1 and 100) not valid;
