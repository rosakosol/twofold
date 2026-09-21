-- ---------------------------------------------------------------------------
-- places: the value constraints on the table itself
-- ---------------------------------------------------------------------------
--
-- These used to run as `authenticated`, because `places_insert_authenticated` was
-- `with check (true)` and this file's header said it "stays that way — find-or-create needs it".
-- It did not stay that way. 20261110000700 moved find-or-create into a security-definer function
-- and dropped both policies, so the table is now deny-all to clients and a direct insert here
-- raises 42501 before any CHECK is reached.
--
-- The constraints are still worth pinning, and they are still the same constraints — so these run
-- as the owner, which is what the RPC does on the caller's behalf. `places_scoping_test` covers
-- the door itself: that clients cannot read or write the table, that the RPC enforces its own
-- validation, and that find-or-create still deduplicates.
--
-- As before, an ordinary insert must keep working: a constraint that rejected real city names
-- would break onboarding, which is worse than the abuse it prevents.
--
-- Coordinates are the ones that matter: a place is shared couple data, and `Geo.distance`, the Home
-- globe and `update_couple_max_distance`'s persisted maximum are all computed from them.

begin;
select plan(10);

-- The normal case, first: this must keep working.
--
-- City/country values here are synthetic rather than real. The table ships seeded with real
-- cities, and `places_city_country_unique` would make a real name fail on a duplicate — which
-- would be a test of the seed data, not of these constraints. Coordinates and formats stay
-- realistic, since those are what is actually under test.
select lives_ok(
  $$insert into public.places (city, country, iata_code, latitude, longitude, timezone)
    values ('Pgtapville', 'Pgtapland', 'MEL', -37.8136, 144.9631, 'Australia/Melbourne')$$,
  'a well-formed place still inserts — find-or-create depends on it'
);

-- A city with no airport and no timezone yet: both columns are nullable and must stay usable.
select lives_ok(
  $$insert into public.places (city, country, latitude, longitude)
    values ('Pgtapton', 'Pgtapland', 33.5904, 130.4017)$$,
  'a place with no IATA code or timezone is still valid'
);

-- Coordinates out of range. Not hypothetical corruption: these feed the distance card and the
-- globe for BOTH partners, and the running maximum distance that does not heal when fixed.
select throws_ok(
  $$insert into public.places (city, country, latitude, longitude)
    values ('Nowhere', 'Nowhere', 9999, 0)$$,
  '23514',
  null,
  'latitude above 90 is refused'
);

select throws_ok(
  $$insert into public.places (city, country, latitude, longitude)
    values ('Nowhere', 'Nowhere', -91, 0)$$,
  '23514',
  null,
  'latitude below -90 is refused'
);

select throws_ok(
  $$insert into public.places (city, country, latitude, longitude)
    values ('Nowhere', 'Nowhere', 0, 181)$$,
  '23514',
  null,
  'longitude above 180 is refused'
);

select throws_ok(
  $$insert into public.places (city, country, latitude, longitude)
    values ('Nowhere', 'Nowhere', 0, -181)$$,
  '23514',
  null,
  'longitude below -180 is refused'
);

-- The exact boundaries are legal — the poles and the antimeridian are real places.
select lives_ok(
  $$insert into public.places (city, country, latitude, longitude)
    values ('Pgtap South Pole', 'Pgtapland', -90, 180)$$,
  'the boundary values themselves are accepted'
);

-- Length bounds: stop a megabyte in a text column, without adjudicating what a place name is.
select throws_ok(
  $$insert into public.places (city, country, latitude, longitude)
    values (repeat('x', 201), 'Nowhere', 0, 0)$$,
  '23514',
  null,
  'an over-long city name is refused'
);

-- A genuinely long real name must still fit. This one is 58 characters.
select lives_ok(
  $$insert into public.places (city, country, latitude, longitude)
    values ('Llanfairpwllgwyngyllgogerychwyrndrobwllllantysiliogogogoch', 'Pgtapland', 53.2206, -4.2003)$$,
  'a very long but real city name still fits'
);

select throws_ok(
  $$insert into public.places (city, country, iata_code, latitude, longitude)
    values ('Nowhere', 'Nowhere', 'NOT-AN-IATA-CODE', 0, 0)$$,
  '23514',
  null,
  'a malformed IATA code is refused'
);

select * from finish();
rollback;
