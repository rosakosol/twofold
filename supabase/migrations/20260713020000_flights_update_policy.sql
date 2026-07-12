-- Restores a client-usable UPDATE policy on flights, mirroring flights_delete_members
-- (20260712100000_flights_delete_policy.sql). The self-reported-flight cleanup
-- (20260712040000_drop_self_reported_flights.sql) dropped the only UPDATE policy that existed
-- (flights_update_self_reported_members_active) and never replaced it, since at the time no
-- client-side flight field was still user-editable. That's no longer true: setting a flight's
-- traveler (FlightTrackingView) and linking/unlinking a flight to a trip (Trip Details) both
-- write directly to this table via BackendService, and have been silently failing ever since —
-- RLS defaults to deny when no policy matches, and these call sites use `try?`, so the failure
-- was never surfaced. Deliberately not restricted to self-reported rows (same reasoning as the
-- delete policy) and not gated on couple_active — updating traveler/trip on a real AeroAPI-
-- tracked flight from your own couple's list is an ordinary edit, not a write against
-- provider-sourced data.

create policy "flights_update_members" on public.flights
  for update using (public.is_couple_member(couple_id));
