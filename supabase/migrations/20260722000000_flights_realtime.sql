-- The `flights` row itself was never added to the realtime publication — only
-- flight_status_events (the discrete event log) was. That meant the live-tracking screen had no
-- way to learn about a server-side update (the 5-minute refresh-due-flights cron writes straight
-- to this row) except an initial load or an explicit pull-to-refresh, so it just sat stale
-- between visits. See BackendService.subscribeToFlightRefresh.
alter publication supabase_realtime add table public.flights;
