-- ---------------------------------------------------------------------------
-- A flight can only be linked to a trip of its own couple
-- ---------------------------------------------------------------------------
--
-- `flights.trip_id` is guarded by its foreign key alone, which proves the trip exists and nothing
-- about whose it is — and a foreign-key check does not consult RLS, so a trip the caller cannot
-- even see passes it. Two ways in:
--
--   * `trip_id` is on the client's update allowlist (20261114002000), so
--       PATCH /rest/v1/flights?id=eq.<own flight> {"trip_id": "<any trip id>"}
--     links a member's flight to another couple's trip.
--   * add-flight inserts whatever `tripId` it is sent, as service_role.
--
-- What it reaches today is small — the other couple cannot see the flight (`can_see_flight`
-- checks the flight's own couple, and `flight_updates_select_members` checks both) — but a flight
-- hanging off a trip it does not belong to is a cross-couple reference nothing else in the schema
-- allows, and the next policy written through `flights.trip_id` would inherit it.
--
-- So the rule goes on the table, for every role: insert or update of `trip_id` (or `couple_id`)
-- must leave the trip's couple and the flight's couple the same. A trigger rather than a composite
-- foreign key because `trips` has no unique (id, couple_id) to point one at, and adding one is a
-- wider change than this needs. `security definer` because the trip being checked is exactly one
-- the caller may not be able to see, and an RLS-scoped lookup would read "not found" as "fine".
-- Raised as 23503, a foreign-key violation, which is what it is.
--
-- The `on delete set null` from the trip still works: a null `trip_id` is always allowed.
-- Existing rows are not re-checked; the trigger fires only on writes to these two columns.
-- (`memories.trip_id` has the same shape and is not touched here.)

create or replace function private.flight_trip_is_the_couples_own()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.trip_id is null then
    return new;
  end if;

  if not exists (select 1 from public.trips where id = new.trip_id and couple_id = new.couple_id) then
    raise exception 'a flight can only be linked to its own couple''s trip'
      using errcode = '23503';
  end if;

  return new;
end;
$$;

revoke all on function private.flight_trip_is_the_couples_own() from public, anon, authenticated;

drop trigger if exists trg_flights_trip_is_the_couples_own on public.flights;
create trigger trg_flights_trip_is_the_couples_own
  before insert or update of trip_id, couple_id on public.flights
  for each row execute function private.flight_trip_is_the_couples_own();

comment on trigger trg_flights_trip_is_the_couples_own on public.flights is
  'trip_id must be null or a trip of the flight''s own couple, for every role; see 20261123000200.';
