-- "Share this flight with my partner" toggle on Add Flight, on by default. Off means the flight
-- (and its events/documents/notification prefs) stays visible only to whoever added it — their
-- partner shouldn't see it in their list, get status events for it, or receive push notifications
-- about it. Notification fan-out (supabase/functions/_shared/notify.ts) runs under the
-- service-role client and bypasses RLS entirely, so it needs its own explicit check — this
-- migration only covers client-visible reads.

alter table public.flights
  add column shared boolean not null default true;

drop policy "flights_select_members" on public.flights;
create policy "flights_select_members" on public.flights
  for select using (
    public.is_couple_member(couple_id)
    and (shared or created_by = auth.uid())
  );

drop policy "flight_status_events_select_members" on public.flight_status_events;
create policy "flight_status_events_select_members" on public.flight_status_events
  for select using (
    exists (
      select 1 from public.flights
      where flights.id = flight_status_events.flight_id
        and public.is_couple_member(flights.couple_id)
        and (flights.shared or flights.created_by = auth.uid())
    )
  );

drop policy "flight_notification_preferences_select_members" on public.flight_notification_preferences;
create policy "flight_notification_preferences_select_members" on public.flight_notification_preferences
  for select using (
    exists (
      select 1 from public.flights
      where flights.id = flight_notification_preferences.flight_id
        and public.is_couple_member(flights.couple_id)
        and (flights.shared or flights.created_by = auth.uid())
    )
  );

drop policy "flight_notification_preferences_insert_own" on public.flight_notification_preferences;
create policy "flight_notification_preferences_insert_own" on public.flight_notification_preferences
  for insert with check (
    profile_id = auth.uid()
    and exists (
      select 1 from public.flights
      where flights.id = flight_notification_preferences.flight_id
        and public.is_couple_member(flights.couple_id)
        and (flights.shared or flights.created_by = auth.uid())
    )
  );

-- flight_documents' select policy has two branches (flight-parented or trip-parented, per
-- flight_documents_one_parent) — only the flight-parented branch is relevant here.
drop policy "flight_documents_select_members" on public.flight_documents;
create policy "flight_documents_select_members" on public.flight_documents
  for select using (
    (flight_id is not null and exists (
      select 1 from public.flights
      where flights.id = flight_documents.flight_id
        and public.is_couple_member(flights.couple_id)
        and (flights.shared or flights.created_by = auth.uid())
    ))
    or (trip_id is not null and exists (
      select 1 from public.trips where trips.id = flight_documents.trip_id and public.is_couple_member(trips.couple_id)
    ))
  );
