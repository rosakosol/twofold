-- Lets a couple member stop tracking a flight (swipe-to-remove on the Trips tab). The
-- previous flights_delete_members_active policy was dropped when flights moved to the
-- AeroAPI-tracked model and never replaced, so there was no client-usable way to remove a
-- flight at all. Deliberately not restricted to self-reported rows (unlike the insert/update
-- policies) — removing a real AeroAPI-tracked flight from your own couple's list is a safe,
-- ordinary "stop tracking this" action, not a write against provider-sourced data.
-- flight_status_events/flight_notification_preferences/flight_documents all cascade on
-- flight_id already (see 20260712000000_flight_tracking.sql), so no orphaned rows.

create policy "flights_delete_members" on public.flights
  for delete using (public.is_couple_member(couple_id));
