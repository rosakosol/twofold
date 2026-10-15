-- ---------------------------------------------------------------------------
-- A flight's tracking state is the server's, not the client's
-- ---------------------------------------------------------------------------
--
-- 20261110001800 put the subscription check into `enable_flight_tracking`, and 20261010000400 put
-- the monthly allowance there, on the understanding that that function is how tracking gets
-- switched on. It is not the only way. `flights_update_members` lets a couple member UPDATE their
-- flight rows, and 20260911000100's blanket `grant all` left `authenticated` holding UPDATE on every
-- column of `public.flights` — `tracking_enabled` included. So:
--
--   PATCH /rest/v1/flights?id=eq.<flight> {"tracking_enabled": true}
--
-- starts AeroAPI polling (refresh-due-flights selects on exactly that column) with no subscription,
-- no allowance check and no `flight_additions` row, so the flight never even counts against the
-- month. A lapsed couple, or one past its five, gets unlimited ~85c tracked flights. The same
-- policy lets them rewrite `status`, `scheduled_*`, `fa_flight_id` and the rest of the AeroAPI-owned
-- fields, which recycles one slot into polling as many different flights, for as long, as they like.
--
-- The app writes exactly two columns of a flight: `trip_id` (BackendService.linkFlightToTrip) and
-- `traveler_ids` (BackendService.updateFlightTravelers). Everything else is written by add-flight,
-- the refresh functions and the AeroAPI webhook as service_role, or by definer functions
-- (enable_flight_tracking, leave_couple, dissolve_couple) running as their owner.
--
-- So this is an allowlist rather than a list of forbidden columns, and a trigger rather than column
-- grants, for the two reasons 20260915000000 gives for profiles: a blanket GRANT cannot reopen a
-- trigger, and a column added to flights later (they are nearly all AeroAPI-owned) is protected
-- without anyone remembering to protect it. `shared` stays writable because the flight privacy
-- policies (20260916000000) are written around the owner being able to set it, and narrowing that
-- is a privacy decision rather than a billing one. `updated_at` is written by trg_flights_touch.
--
-- Same caller test as 20260915000000, and not `security definer` for the same reason: it must see
-- the caller's role, and anon/authenticated are exactly the roles a client can reach.

create or replace function private.reject_client_flight_writes()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_client_columns constant text[] := array['trip_id', 'traveler_ids', 'shared', 'updated_at'];
begin
  if current_user not in ('anon', 'authenticated') then
    return new;
  end if;

  -- jsonb minus the allowlist on both sides: equal means only allowlisted columns moved. Compared
  -- as jsonb so a null-to-value change is a difference, which `<>` on the columns would miss.
  if (to_jsonb(new) - v_client_columns) is distinct from (to_jsonb(old) - v_client_columns) then
    raise exception 'flight tracking and schedule fields are set by the server, not by the client'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

revoke all on function private.reject_client_flight_writes() from public, anon, authenticated;

drop trigger if exists trg_flights_guard_server_columns on public.flights;
create trigger trg_flights_guard_server_columns
  before update on public.flights
  for each row execute function private.reject_client_flight_writes();

comment on trigger trg_flights_guard_server_columns on public.flights is
  'Clients may change only trip_id, traveler_ids and shared. tracking_enabled in particular starts '
  'paid AeroAPI polling and is set only through enable_flight_tracking or add-flight; see 20261114002000.';
