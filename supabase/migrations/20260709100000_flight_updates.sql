-- Traveler self-reported flight updates (meal service, disruptions, going to
-- sleep, etc.), surfaced to their partner in real time via Supabase Realtime.
-- Only the trip's traveler may add updates; either partner can read them.

create type public.flight_update_kind as enum ('meal_service', 'disruption', 'going_to_sleep', 'custom');

create table public.flight_updates (
  id uuid primary key default gen_random_uuid(),
  flight_id uuid not null references public.flights (id) on delete cascade,
  kind public.flight_update_kind not null,
  note text,
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now()
);

create index flight_updates_flight_id_idx on public.flight_updates (flight_id);

alter table public.flight_updates enable row level security;

create policy "flight_updates_select_members" on public.flight_updates
  for select using (
    exists (
      select 1 from public.flights
      join public.trips on trips.id = flights.trip_id
      where flights.id = flight_updates.flight_id
        and public.is_couple_member(trips.couple_id)
    )
  );

-- Only the traveler on this flight (not their partner) can log updates, and
-- only while the couple is still active.
create policy "flight_updates_insert_traveler_active" on public.flight_updates
  for insert with check (
    created_by = auth.uid()
    and exists (
      select 1 from public.flights
      join public.trips on trips.id = flights.trip_id
      where flights.id = flight_updates.flight_id
        and trips.traveler_id = auth.uid()
        and public.is_couple_active(trips.couple_id)
    )
  );

create policy "flight_updates_delete_own" on public.flight_updates
  for delete using (created_by = auth.uid());

-- Required for postgres_changes Realtime subscriptions to fire on this table.
alter publication supabase_realtime add table public.flight_updates;
