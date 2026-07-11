-- Live flight tracking (AeroAPI-backed). Redefines `flights` from a schedule-only, 1:1-with-
-- trip table into a couple-scoped, independently-trackable entity that can optionally link to
-- a trip. No real user data exists for flights yet, so this clears existing rows rather than
-- attempting a value-preserving migration of the old schedule-only shape.
--
-- Flights are provider-sourced: every write comes from a trusted Edge Function using the
-- service role key (which bypasses RLS), never directly from a client. Only select policies
-- are defined for `flights` and `flight_status_events` below.

truncate table public.flights cascade;

alter table public.flights
  drop constraint flights_trip_id_fkey,
  drop constraint flights_trip_id_key;

alter table public.flights
  alter column trip_id drop not null,
  add constraint flights_trip_id_fkey foreign key (trip_id) references public.trips (id) on delete set null,
  drop column flight_number,
  drop column origin_id,
  drop column destination_id,
  drop column scheduled_departure,
  drop column scheduled_arrival,
  add column couple_id uuid references public.couples (id) on delete cascade,
  add column created_by uuid references public.profiles (id),
  add column fa_flight_id text,
  add column flight_number_iata text,
  add column flight_number_icao text,
  add column airline_name text,
  add column airline_code text,
  add column airline_logo_url text,
  -- Denormalized airport snapshots, not a `places` FK: AeroAPI covers far more airports than
  -- the curated `places.commonCities` seed list, and this is provider truth data, not
  -- user-curated city data.
  add column origin_iata text,
  add column origin_icao text,
  add column origin_name text,
  add column origin_city text,
  add column origin_timezone text,
  add column origin_latitude double precision,
  add column origin_longitude double precision,
  add column destination_iata text,
  add column destination_icao text,
  add column destination_name text,
  add column destination_city text,
  add column destination_timezone text,
  add column destination_latitude double precision,
  add column destination_longitude double precision,
  add column aircraft_type text,
  add column registration text,
  add column route text,
  add column scheduled_out timestamptz,
  add column scheduled_off timestamptz,
  add column scheduled_on timestamptz,
  add column scheduled_in timestamptz,
  add column estimated_out timestamptz,
  add column estimated_off timestamptz,
  add column estimated_on timestamptz,
  add column estimated_in timestamptz,
  add column actual_out timestamptz,
  add column actual_off timestamptz,
  add column actual_on timestamptz,
  add column actual_in timestamptz,
  add column departure_delay_seconds int,
  add column arrival_delay_seconds int,
  add column terminal_origin text,
  add column gate_origin text,
  add column terminal_destination text,
  add column gate_destination text,
  add column baggage_claim text,
  add column cancelled boolean not null default false,
  add column diverted boolean not null default false,
  add column status text not null default 'scheduled',
  add column position_latitude double precision,
  add column position_longitude double precision,
  add column position_altitude double precision,
  add column position_groundspeed double precision,
  add column position_heading double precision,
  add column position_updated_at timestamptz,
  add column weather_origin jsonb,
  add column weather_destination jsonb,
  add column weather_updated_at timestamptz,
  add column last_refreshed_at timestamptz,
  add column tracking_enabled boolean not null default true;

alter table public.flights alter column couple_id set not null;

alter table public.flights add constraint flights_status_check
  check (status in (
    'scheduled', 'boarding', 'departed', 'in_air', 'landing_soon', 'landed',
    'arrived', 'delayed', 'cancelled', 'diverted'
  ));

drop index if exists flights_trip_id_idx;
create index flights_trip_id_idx on public.flights (trip_id);
create index flights_couple_id_idx on public.flights (couple_id);
create index flights_fa_flight_id_idx on public.flights (fa_flight_id);
create index flights_tracking_enabled_idx on public.flights (tracking_enabled) where tracking_enabled;

drop policy "flights_select_members" on public.flights;
drop policy "flights_insert_members_active" on public.flights;
drop policy "flights_update_members_active" on public.flights;
drop policy "flights_delete_members_active" on public.flights;

create policy "flights_select_members" on public.flights
  for select using (public.is_couple_member(couple_id));

-- Narrow exception: a couple member may insert/update a *self-reported* flight row
-- (fa_flight_id is null — no real provider tracking behind it, e.g. the optional flight
-- number typed in during manual trip creation). Anything with a fa_flight_id is real
-- AeroAPI-tracked data and stays service-role-only, per the comment above.
create policy "flights_insert_self_reported_members_active" on public.flights
  for insert with check (
    fa_flight_id is null
    and created_by = auth.uid()
    and public.is_couple_member(couple_id)
    and public.is_couple_active(couple_id)
  );

create policy "flights_update_self_reported_members_active" on public.flights
  for update using (
    fa_flight_id is null
    and public.is_couple_member(couple_id)
    and public.is_couple_active(couple_id)
  );

-- ---------------------------------------------------------------------------
-- Flight status events: reverse-chronological, provider-sourced event history.
-- Distinct from the existing `flight_updates` table (traveler self-reported
-- meal/disruption/sleep notes) — kept separate to avoid conflating the two.
-- ---------------------------------------------------------------------------

create type public.flight_status_event_type as enum (
  'scheduled', 'delay', 'gate_change', 'terminal_change', 'departed', 'airborne',
  'arrival_time_change', 'landed', 'arrived_at_gate', 'baggage_claim', 'cancelled', 'diverted'
);

create table public.flight_status_events (
  id uuid primary key default gen_random_uuid(),
  flight_id uuid not null references public.flights (id) on delete cascade,
  type public.flight_status_event_type not null,
  previous_value text,
  new_value text,
  occurred_at timestamptz not null default now(),
  source text not null default 'poll',
  created_at timestamptz not null default now(),
  constraint flight_status_events_source_check check (source in ('poll', 'webhook'))
);

create index flight_status_events_flight_id_idx on public.flight_status_events (flight_id, occurred_at desc);

alter table public.flight_status_events enable row level security;

create policy "flight_status_events_select_members" on public.flight_status_events
  for select using (
    exists (
      select 1 from public.flights
      where flights.id = flight_status_events.flight_id
        and public.is_couple_member(flights.couple_id)
    )
  );

alter publication supabase_realtime add table public.flight_status_events;

-- ---------------------------------------------------------------------------
-- Per-partner, per-flight notification preferences.
-- ---------------------------------------------------------------------------

create table public.flight_notification_preferences (
  id uuid primary key default gen_random_uuid(),
  flight_id uuid not null references public.flights (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  gate_terminal_changes boolean not null default true,
  delay_or_cancellation boolean not null default true,
  departure boolean not null default true,
  landing boolean not null default true,
  arrival_at_gate boolean not null default true,
  baggage_claim_update boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint flight_notification_preferences_unique unique (flight_id, profile_id)
);

create trigger trg_flight_notification_preferences_touch before update on public.flight_notification_preferences
  for each row execute function public.touch_updated_at();

alter table public.flight_notification_preferences enable row level security;

create policy "flight_notification_preferences_select_members" on public.flight_notification_preferences
  for select using (
    exists (
      select 1 from public.flights
      where flights.id = flight_notification_preferences.flight_id
        and public.is_couple_member(flights.couple_id)
    )
  );

create policy "flight_notification_preferences_insert_own" on public.flight_notification_preferences
  for insert with check (
    profile_id = auth.uid()
    and exists (
      select 1 from public.flights
      where flights.id = flight_notification_preferences.flight_id
        and public.is_couple_member(flights.couple_id)
    )
  );

create policy "flight_notification_preferences_update_own" on public.flight_notification_preferences
  for update using (profile_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Flight documents (boarding passes, itineraries) — mirrors the memory_photos
-- pattern: private bucket, signed-URL reads, position-agnostic child rows.
-- Attached to exactly one of a flight or a trip.
-- ---------------------------------------------------------------------------

create table public.flight_documents (
  id uuid primary key default gen_random_uuid(),
  flight_id uuid references public.flights (id) on delete cascade,
  trip_id uuid references public.trips (id) on delete cascade,
  uploaded_by uuid not null references public.profiles (id),
  doc_type text not null default 'other',
  file_path text not null,
  original_filename text,
  content_type text,
  created_at timestamptz not null default now(),
  constraint flight_documents_doc_type_check check (doc_type in ('boarding_pass', 'itinerary', 'other')),
  constraint flight_documents_one_parent check (
    (flight_id is not null and trip_id is null) or (flight_id is null and trip_id is not null)
  )
);

create index flight_documents_flight_id_idx on public.flight_documents (flight_id);
create index flight_documents_trip_id_idx on public.flight_documents (trip_id);

alter table public.flight_documents enable row level security;

create policy "flight_documents_select_members" on public.flight_documents
  for select using (
    (flight_id is not null and exists (
      select 1 from public.flights where flights.id = flight_documents.flight_id and public.is_couple_member(flights.couple_id)
    ))
    or (trip_id is not null and exists (
      select 1 from public.trips where trips.id = flight_documents.trip_id and public.is_couple_member(trips.couple_id)
    ))
  );

create policy "flight_documents_insert_members_active" on public.flight_documents
  for insert with check (
    uploaded_by = auth.uid()
    and (
      (flight_id is not null and exists (
        select 1 from public.flights where flights.id = flight_documents.flight_id and public.is_couple_member(flights.couple_id)
      ))
      or (trip_id is not null and exists (
        select 1 from public.trips where trips.id = flight_documents.trip_id
          and public.is_couple_member(trips.couple_id) and public.is_couple_active(trips.couple_id)
      ))
    )
  );

create policy "flight_documents_delete_members" on public.flight_documents
  for delete using (
    (flight_id is not null and exists (
      select 1 from public.flights where flights.id = flight_documents.flight_id and public.is_couple_member(flights.couple_id)
    ))
    or (trip_id is not null and exists (
      select 1 from public.trips where trips.id = flight_documents.trip_id and public.is_couple_member(trips.couple_id)
    ))
  );

insert into storage.buckets (id, name, public)
values ('flight-documents', 'flight-documents', false)
on conflict (id) do nothing;

-- Path convention: {couple_id}/{flight_or_trip_id}/{uuid}.{ext} — mirrors memory-photos so the
-- couple_id is directly readable from the path without a DB lookup inside the storage policy.
create policy "flight_documents_storage_select_members" on storage.objects
  for select using (
    bucket_id = 'flight-documents'
    and public.is_couple_member((storage.foldername(name))[1]::uuid)
  );

create policy "flight_documents_storage_insert_members_active" on storage.objects
  for insert with check (
    bucket_id = 'flight-documents'
    and public.is_couple_member((storage.foldername(name))[1]::uuid)
    and public.is_couple_active((storage.foldername(name))[1]::uuid)
  );

create policy "flight_documents_storage_delete_members" on storage.objects
  for delete using (
    bucket_id = 'flight-documents'
    and public.is_couple_member((storage.foldername(name))[1]::uuid)
  );

-- ---------------------------------------------------------------------------
-- Device push tokens — foundation for real APNs delivery. Each user manages
-- only their own row; `send-flight-notification` reads across the couple
-- using the service role key, which bypasses RLS.
-- ---------------------------------------------------------------------------

create table public.device_push_tokens (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  apns_token text not null unique,
  environment text not null default 'production',
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  constraint device_push_tokens_environment_check check (environment in ('sandbox', 'production'))
);

create index device_push_tokens_profile_id_idx on public.device_push_tokens (profile_id);

alter table public.device_push_tokens enable row level security;

create policy "device_push_tokens_select_own" on public.device_push_tokens
  for select using (profile_id = auth.uid());

create policy "device_push_tokens_insert_own" on public.device_push_tokens
  for insert with check (profile_id = auth.uid());

create policy "device_push_tokens_update_own" on public.device_push_tokens
  for update using (profile_id = auth.uid());

create policy "device_push_tokens_delete_own" on public.device_push_tokens
  for delete using (profile_id = auth.uid());
