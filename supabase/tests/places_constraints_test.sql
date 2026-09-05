-- ---------------------------------------------------------------------------
-- places: what a signed-in user is allowed to write
-- ---------------------------------------------------------------------------
--
-- `places_insert_authenticated` is `with check (true)` and stays that way — find-or-create needs
-- it. These pin the value constraints that bound what can be written through that door, and, just
-- as importantly, pin that an ordinary insert still works. A constraint that rejected real city
-- names would break onboarding, which is a worse outcome than the abuse it prevents.
--
-- Coordinates are the ones that matter: a place is shared couple data, and `Geo.distance`, the Home
-- globe and `update_couple_max_distance`'s persisted maximum are all computed from them.

begin;
select plan(10);

set local role authenticated;
set local request.jwt.claims = '{"sub":"c0ffee00-0000-4000-8000-000000000001","role":"authenticated"}';

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
