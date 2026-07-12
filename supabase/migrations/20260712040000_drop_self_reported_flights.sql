-- Flights are never self-reported anymore — every flight is now created exclusively through
-- the real AeroAPI-backed search (Twofold/Twofold/Features/Flights/AddFlight/), persisted only
-- by the add-flight/refresh-flight Edge Functions under the service role key. The client-side
-- "insert/update a flight row with fa_flight_id IS NULL" exception these two policies carved
-- out existed solely to support that now-removed self-report pathway (see
-- BackendService.insertSelfReportedFlight, removed) — drop them so a couple member can no
-- longer write a flights row directly at all; `flights_select_members` (read) is unaffected.

drop policy if exists "flights_insert_self_reported_members_active" on public.flights;
drop policy if exists "flights_update_self_reported_members_active" on public.flights;
