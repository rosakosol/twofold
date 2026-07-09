-- Flights: one optional flight per trip. Status/progress/timeline stay
-- client-computed from scheduled_departure/scheduled_arrival (see MockData.activeFlight)
-- rather than tracked here — this table only needs identity + schedule.

create table public.flights (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null unique references public.trips (id) on delete cascade,
  flight_number text not null,
  origin_id uuid not null references public.places (id),
  destination_id uuid not null references public.places (id),
  scheduled_departure timestamptz not null,
  scheduled_arrival timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index flights_trip_id_idx on public.flights (trip_id);

create trigger trg_flights_touch before update on public.flights
  for each row execute function public.touch_updated_at();

alter table public.flights enable row level security;

-- Mirrors the trips policies: any couple member can read; writes require
-- membership in a couple that's still active. Membership/activity is derived
-- via the parent trip's couple_id since flights doesn't store one directly.
create policy "flights_select_members" on public.flights
  for select using (
    exists (
      select 1 from public.trips
      where trips.id = flights.trip_id
        and public.is_couple_member(trips.couple_id)
    )
  );

create policy "flights_insert_members_active" on public.flights
  for insert with check (
    exists (
      select 1 from public.trips
      where trips.id = flights.trip_id
        and public.is_couple_member(trips.couple_id)
        and public.is_couple_active(trips.couple_id)
    )
  );

create policy "flights_update_members_active" on public.flights
  for update using (
    exists (
      select 1 from public.trips
      where trips.id = flights.trip_id
        and public.is_couple_member(trips.couple_id)
        and public.is_couple_active(trips.couple_id)
    )
  );

create policy "flights_delete_members_active" on public.flights
  for delete using (
    exists (
      select 1 from public.trips
      where trips.id = flights.trip_id
        and public.is_couple_member(trips.couple_id)
        and public.is_couple_active(trips.couple_id)
    )
  );
