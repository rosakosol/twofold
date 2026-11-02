-- ---------------------------------------------------------------------------
-- A write that changes nothing on a flight is not a write
-- ---------------------------------------------------------------------------
--
-- Every change to a `flights` row goes out over realtime, and both partners' phones answer each
-- one by rebuilding their whole widget snapshot. Some of the cron's writes changed nothing: the
-- live-position pass writes the last known position onto every couple's copy of an airborne flight
-- every minute, and through an oceanic coverage gap (hours, on the long-haul routes this app is
-- for) that is the same position each time. `trg_flights_touch` then stamped a fresh updated_at,
-- so the identical write still became a change, a realtime event and two widget rebuilds a minute.
--
-- Postgres's own `suppress_redundant_updates_trigger` drops an update whose new row is identical
-- to the old one. Triggers of the same kind fire in name order, so it is named to run before
-- `trg_flights_guard_server_columns` and `trg_flights_touch`; after the touch, no row would ever be
-- identical. A write the app makes that changes nothing also stops being a realtime event, and
-- nothing in the app reads a row count back from a flight update.

create trigger trg_flights_a_skip_unchanged
  before update on public.flights
  for each row execute function suppress_redundant_updates_trigger();
