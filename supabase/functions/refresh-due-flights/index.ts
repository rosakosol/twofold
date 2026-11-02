// Cron entrypoint (see supabase/migrations/20260712000100_flight_refresh_cron.sql) — pg_cron
// fires every 5 minutes and asks this function to refresh whatever is actually due per its own
// tiered cadence. Not meant to be called by anything except that cron job, which authenticates
// with the service role key; a stray public request is rejected outright so it can't trigger a
// mass AeroAPI-billing run.
//
// Cadence (checked in TS against each row's scheduled_out/last_refreshed_at):
//   - in the 10 minutes leading up to best-known departure, leading up to best-known arrival, OR
//     already past best-known arrival with no landed/arrived confirmation yet: refresh if stale
//     >1 min (the cron itself now fires every minute — see
//     20260826000000_flight_refresh_cron_every_minute.sql — specifically so this tier can
//     actually act that fast; a 5-minute cron can't poll faster than every 5 minutes no
//     matter how tight this threshold is)
//   - currently boarding/departed/in_air/landing_soon, but *not* within either 10-minute window
//     above (i.e. genuine mid-cruise, or an early boarding call well before departure): refresh
//     if stale >12 min. Was 2 min — cost data showed this tier alone was responsible for most of
//     the /flights/{ident} bill (291 calls/$1.46 in 24h), since it applied for a flight's entire
//     multi-hour cruise segment, not just the moments around takeoff/landing that actually need
//     near-real-time freshness. The on-map/Live-Activity marker's own movement doesn't depend on
//     this cadence at all (see FlightMapView's markerCoordinate — pure elapsed-time
//     interpolation), so this only trades off how quickly a mid-flight ETA/delay correction
//     shows up, not how smoothly the plane appears to move.
//   - within 2h of departure but not yet active: refresh if stale >2 min
//   - 2h-24h to departure: refresh if stale >15 min
//   - more than 24h to departure: refresh only if last_refreshed_at is null or >6h old
//   - tracking_enabled = false: never selected (query excludes it)
//   - already arrived/landed/cancelled/diverted: selected, but never polls AeroAPI again — only
//     reconcileOverdueArrival's archive-after-2h check runs for these (see below)
//
// Processes flights sequentially with a short delay between AeroAPI calls rather than in
// parallel, to avoid bursting rate limits — this is a background job, latency doesn't matter.

import { createClient } from "jsr:@supabase/supabase-js@2";
// The run itself lives in _shared so tests can import it — this file's top-level Deno.serve makes
// it unimportable. See _shared/flight-refresh-run.ts and _shared/flight-schedule.test.ts.
import { runDueFlightRefresh } from "../_shared/flight-refresh-run.ts";

Deno.serve(async (req) => {
  const expected = `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`;
  if (req.headers.get("Authorization") !== expected) {
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  }

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const result = await runDueFlightRefresh(serviceClient);
  if (!result.ok) return Response.json({ error: result.error }, { status: result.status });
  return Response.json({ refreshed: result.refreshed, skipped: result.skipped });
});

/* To invoke locally:

  1. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  2. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/refresh-due-flights' \
    --header 'Authorization: Bearer <service-role-key>' \
    --data '{}'

*/
