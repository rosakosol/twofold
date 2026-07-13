// Cron entrypoint (see supabase/migrations/20260712000100_flight_refresh_cron.sql) — pg_cron
// fires every 5 minutes and asks this function to refresh whatever is actually due per its own
// tiered cadence. Not meant to be called by anything except that cron job, which authenticates
// with the service role key; a stray public request is rejected outright so it can't trigger a
// mass AeroAPI-billing run.
//
// Cadence (checked in TS against each row's scheduled_out/last_refreshed_at):
//   - more than 24h to departure: refresh only if last_refreshed_at is null or >6h old
//   - 2h-24h to departure: refresh if stale >15 min
//   - within 2h of departure, or currently boarding/departed/in_air/landing_soon: refresh if
//     stale >2 min
//   - tracking_enabled = false or status = arrived: never selected (query already excludes them)
//
// Processes flights sequentially with a short delay between AeroAPI calls rather than in
// parallel, to avoid bursting rate limits — this is a background job, latency doesn't matter.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { type FlightRow, maybeRefreshWeather, refreshOneFlight } from "../_shared/flight-sync.ts";
import { notifyPreDeparture } from "../_shared/notify.ts";

const INTER_CALL_DELAY_MS = 200;

const ACTIVE_STATUSES = ["boarding", "departed", "in_air", "landing_soon"];

function isDue(flight: FlightRow, now: number): boolean {
  if (!flight.scheduled_out) return true; // no schedule to gauge against — always worth a look
  const msToDeparture = new Date(flight.scheduled_out).getTime() - now;
  const lastRefreshedMs = flight.last_refreshed_at ? new Date(flight.last_refreshed_at).getTime() : null;
  const staleMs = lastRefreshedMs === null ? Infinity : now - lastRefreshedMs;

  const isActive = ACTIVE_STATUSES.includes(flight.status);
  if (isActive || msToDeparture <= 2 * 60 * 60 * 1000) {
    return staleMs > 2 * 60 * 1000;
  }
  if (msToDeparture <= 24 * 60 * 60 * 1000) {
    return staleMs > 15 * 60 * 1000;
  }
  return lastRefreshedMs === null || staleMs > 6 * 60 * 60 * 1000;
}

// "Wish them a safe flight" nudge to the *other* partner — fires once per flight, guarded by
// pre_departure_notified (see 20260717030000_flight_pre_departure_notified.sql), while it's
// within 10 minutes of its best-known departure time and hasn't actually left yet. Near-departure
// flights are refreshed on essentially every cron tick already (isDue's 2-minute staleness
// threshold is well under this function's 5-minute schedule), so checking only right after a
// due-refresh is a safe simplification rather than re-evaluating every skipped flight too.
const PRE_DEPARTURE_WINDOW_MS = 10 * 60 * 1000;

function isDueForPreDepartureReminder(flight: FlightRow, now: number): boolean {
  if (flight.pre_departure_notified || flight.actual_out) return false;
  const bestDeparture = flight.estimated_out ?? flight.scheduled_out;
  if (!bestDeparture) return false;
  return new Date(bestDeparture).getTime() - now <= PRE_DEPARTURE_WINDOW_MS;
}

Deno.serve(async (req) => {
  const expected = `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`;
  if (req.headers.get("Authorization") !== expected) {
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  }

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: flights, error } = await serviceClient
    .from("flights")
    .select("*")
    .eq("tracking_enabled", true)
    .neq("status", "arrived");

  if (error) {
    console.error("[refresh-due-flights] failed to load flights:", error.message);
    return Response.json({ error: "Failed to load flights" }, { status: 500 });
  }

  let refreshed = 0;
  let skipped = 0;
  const now = Date.now();

  for (const flight of (flights ?? []) as FlightRow[]) {
    if (!isDue(flight, now)) {
      skipped++;
      continue;
    }

    try {
      const updated = await refreshOneFlight(serviceClient, flight);
      refreshed++;

      if (updated && isDueForPreDepartureReminder(updated, now)) {
        try {
          await notifyPreDeparture(serviceClient, updated.id);
          await serviceClient.from("flights").update({ pre_departure_notified: true }).eq("id", updated.id);
        } catch (err) {
          // Left unmarked on failure so the next cron tick retries — same reasoning as everything
          // else in this loop being best-effort per flight.
          console.error(`[refresh-due-flights] pre-departure reminder failed for ${flight.id}:`, (err as Error).message);
        }
      }
    } catch (err) {
      console.error(`[refresh-due-flights] refresh failed for ${flight.id}:`, (err as Error).message);
    }

    try {
      await maybeRefreshWeather(serviceClient, flight);
    } catch (err) {
      console.error(`[refresh-due-flights] weather refresh failed for ${flight.id}:`, (err as Error).message);
    }

    await new Promise((resolve) => setTimeout(resolve, INTER_CALL_DELAY_MS));
  }

  return Response.json({ refreshed, skipped });
});

/* To invoke locally:

  1. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  2. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/refresh-due-flights' \
    --header 'Authorization: Bearer <service-role-key>' \
    --data '{}'

*/
