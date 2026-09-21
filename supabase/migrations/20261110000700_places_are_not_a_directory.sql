-- `places` is readable in full by every signed-in user, and writable by them too.
--
-- ---------------------------------------------------------------------------
-- What is in it
-- ---------------------------------------------------------------------------
--
-- `places_select_authenticated` is `using (true)`, on a table with `city`, `country`, `latitude`,
-- `longitude` and `created_at` and no owner column. Most rows are seeded cities and harmless. The
-- rest are not: `MemoryLocationSearchView` writes whatever the person typed, or whatever Core
-- Location named a dropped pin, with an exact coordinate. So `select city, country, created_at
-- from places` returned, to any signed-in Twofold user, the street addresses and venues other
-- couples have tagged memories at, with first-seen timestamps.
--
-- 20261022000000 coarsened home coordinates and deliberately left memory-referenced rows alone,
-- reasoning that "the name already says where it is, so rounding protects nothing". That is right
-- about the coordinate and says nothing about the row being globally readable, which is the half
-- left standing.
--
-- It is genuinely mitigated, which is why this is not urgent: the rows are unattributable. There
-- is no owner column and `memories` is scoped to its couple, so it is a list of places with no
-- people attached. And the common path is already safe — a memory's default location goes through
-- `HomeLocationService`, which coarsens to city level. Only a deliberately typed address or a
-- dropped pin is precise.
--
-- ---------------------------------------------------------------------------
-- And it is writable
-- ---------------------------------------------------------------------------
--
-- `places_insert_authenticated` is `with check (true)`, so any signed-in user can insert unbounded
-- rows into a shared gazetteer with no validation — one of only two `true` writes in the schema.
--
-- ---------------------------------------------------------------------------
-- What replaces them
-- ---------------------------------------------------------------------------
--
-- Both client paths become security-definer functions, which is what lets the policies go away
-- entirely rather than being narrowed into something elaborate and fragile:
--
--   * `places_by_ids` — the app's `fetchPlaces`. An id is only obtainable from a row the caller
--     can already read (a trip, a memory, a profile), all of which are RLS-scoped to their couple,
--     so possession of an id is a reasonable proxy for being allowed to resolve it. What goes away
--     is enumeration: there is no longer a query that returns rows you were not already pointed at.
--
--   * `find_or_create_place` — the app's `findOrCreatePlaceID`, which had to read by (city,
--     country) to honour the unique constraint and insert when it missed. Both halves move
--     server-side, so the client never selects on a name it did not already have, and the inserted
--     values are validated rather than taken on trust.
--
-- No SQL function anywhere references this table, so nothing internal depends on the policies.

create or replace function public.places_by_ids(p_ids uuid[])
returns setof public.places
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  -- Bounded for the same reason `storage-url` bounds its path list: an unbounded array from a
  -- client is a query somebody can make arbitrarily expensive. The app chunks to match.
  if p_ids is null or array_length(p_ids, 1) is null then
    return;
  end if;
  if array_length(p_ids, 1) > 500 then
    raise exception 'p_ids is limited to 500 per call';
  end if;

  return query select * from public.places where id = any(p_ids);
end;
$$;

create or replace function public.find_or_create_place(
  p_city text,
  p_country text,
  p_iata_code text default null,
  p_latitude double precision default null,
  p_longitude double precision default null,
  p_timezone text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  -- Validation the `with check (true)` policy never did. A gazetteer shared by every couple should
  -- not accept a novel as a city name.
  if p_city is null or length(btrim(p_city)) = 0 or length(p_city) > 200 then
    raise exception 'p_city must be 1-200 characters';
  end if;
  if p_country is null or length(btrim(p_country)) = 0 or length(p_country) > 200 then
    raise exception 'p_country must be 1-200 characters';
  end if;
  if p_iata_code is not null and length(p_iata_code) > 8 then
    raise exception 'p_iata_code is too long';
  end if;
  if p_timezone is not null and length(p_timezone) > 100 then
    raise exception 'p_timezone is too long';
  end if;
  if p_latitude is not null and (p_latitude < -90 or p_latitude > 90) then
    raise exception 'p_latitude is out of range';
  end if;
  if p_longitude is not null and (p_longitude < -180 or p_longitude > 180) then
    raise exception 'p_longitude is out of range';
  end if;

  select id into v_id from public.places
  where city = p_city and country = p_country
  limit 1;
  if v_id is not null then
    return v_id;
  end if;

  -- `on conflict` rather than a bare insert: two people adding a trip to the same new city at the
  -- same moment both miss the select above, and the unique constraint would fail the loser.
  insert into public.places (city, country, iata_code, latitude, longitude, timezone)
  values (btrim(p_city), btrim(p_country), p_iata_code, p_latitude, p_longitude, p_timezone)
  on conflict (city, country) do nothing
  returning id into v_id;

  if v_id is null then
    select id into v_id from public.places where city = p_city and country = p_country limit 1;
  end if;

  return v_id;
end;
$$;

revoke all on function public.places_by_ids(uuid[]) from public, anon;
revoke all on function public.find_or_create_place(text, text, text, double precision, double precision, text)
  from public, anon;
grant execute on function public.places_by_ids(uuid[]) to authenticated, service_role;
grant execute on function public.find_or_create_place(text, text, text, double precision, double precision, text)
  to authenticated, service_role;

-- RLS stays on with no policies at all, which is deny-all for anon and authenticated. The two
-- functions above are the only way in, and service_role is unaffected.
drop policy if exists "places_select_authenticated" on public.places;
drop policy if exists "places_insert_authenticated" on public.places;
