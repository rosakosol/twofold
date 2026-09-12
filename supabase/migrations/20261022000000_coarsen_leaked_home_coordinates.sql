-- ---------------------------------------------------------------------------
-- Take the house-level coordinates back out of the cities people live in
-- ---------------------------------------------------------------------------
--
-- The companion to the app-side fix in `HomeLocationService.cityLevelCoordinate(for:)`. That stops
-- new fixes being published; this deals with the ones already written.
--
-- What was wrong: `public.places` is shared reference data, deduplicated on `(city, country)` and
-- readable by every signed-in user (`places_select_authenticated ... using (true)`).
-- `HomeLocationService` put the raw CoreLocation reading into the `Place` it built, and
-- `findOrCreatePlaceID` inserts that row the first time anyone reaches a given city. So the first
-- person to open the app in a town wrote a building-level coordinate as that town's, visible to
-- everybody, and every later user of the same city silently inherited it.
--
-- ---------------------------------------------------------------------------
-- Why only the rows a profile calls home
-- ---------------------------------------------------------------------------
--
-- There is no provenance column, so no row says how its coordinates were obtained. What the
-- references tell us is enough for the case that matters:
--
--   * Referenced by `profiles.home_place_id` / `partner_home_place_id` — a city somebody lives in.
--     Whether it arrived from a GPS fix or the city picker, the coordinate should be the city's and
--     nothing finer. These are the rows the leak actually produced, and they are the ones that map
--     a name to a home. Rounded here.
--
--   * Referenced only by `memories.place_id` — ambiguous, and deliberately left alone.
--     `MemoryLocationSearchView`'s typed address and dropped pin write a coordinate the user chose
--     for a place they named themselves, often a street or a POI; the name already says where it
--     is, so rounding protects nothing and would visibly drag the pin off the spot they picked.
--     Some of these are instead a fix taken at "use my current location", which this does not
--     catch. Inspect them by eye rather than by rule — a locality name sitting at 5-decimal
--     precision is the shape to look for.
--
--   * `iata_code is not null` — seeded cities and airports, real centres. Untouched.
--
-- ---------------------------------------------------------------------------
-- Rounding rather than repair
-- ---------------------------------------------------------------------------
--
-- One decimal place is ~11km, matching the fallback the app now uses where it has no bundled city
-- centre to snap to. Postgres cannot geocode, so a true centre is not available here; 11km is
-- coarse enough that the row cannot point at a property, and every consumer of these coordinates
-- is indifferent at that scale — the globe arc, `Geo.distance` between two cities usually hundreds
-- of kilometres apart, and a weather lookup that returns the same forecast either way.
--
-- `update_couple_max_distance` keeps a persisted running maximum that does not heal when a row
-- changes (see 20260919000000's header). A shift of at most ~5.5km per endpoint cannot meaningfully
-- move it, so it is left as is rather than recomputed.
--
-- Idempotent: rounding an already-rounded value changes nothing, so re-running is a no-op.

do $$
declare
  v_rounded integer;
begin
  with home_places as (
    select home_place_id as id from public.profiles where home_place_id is not null
    union
    select partner_home_place_id from public.profiles where partner_home_place_id is not null
  )
  update public.places p
  set latitude  = round(p.latitude::numeric, 1)::float8,
      longitude = round(p.longitude::numeric, 1)::float8
  where p.id in (select id from home_places)
    and p.iata_code is null
    and (
      p.latitude  <> round(p.latitude::numeric, 1)::float8
      or p.longitude <> round(p.longitude::numeric, 1)::float8
    );

  get diagnostics v_rounded = row_count;
  raise notice 'places: coarsened % home-city row(s) to ~11km.', v_rounded;
end;
$$;
