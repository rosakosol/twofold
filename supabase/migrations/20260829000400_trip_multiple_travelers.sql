-- Trips could only ever have a single traveler — no way to mark that both partners went
-- together. Mirrors the same fix already applied to flights (see
-- 20260730000000_flight_multiple_travelers.sql): replaces the scalar traveler_id with an array
-- so 0, 1, or 2 of the couple's members can be recorded, without needing a join table for a
-- value that's always at most 2 elements.
alter table public.trips
  add column traveler_ids uuid[] not null default '{}';

update public.trips
  set traveler_ids = array[traveler_id]
  where traveler_id is not null;

-- "flight_updates_insert_traveler_active" (20260709100000_flight_updates.sql) reads
-- trips.traveler_id directly, so it has to be repointed at the new array column before that
-- column can be dropped below — otherwise the drop fails outright on the dependency.
drop policy if exists "flight_updates_insert_traveler_active" on public.flight_updates;

create policy "flight_updates_insert_traveler_active" on public.flight_updates
  for insert with check (
    created_by = auth.uid()
    and exists (
      select 1 from public.flights
      join public.trips on trips.id = flights.trip_id
      where flights.id = flight_updates.flight_id
        and auth.uid() = any (trips.traveler_ids)
        and public.is_couple_active(trips.couple_id)
    )
  );

alter table public.trips
  drop column traveler_id;
