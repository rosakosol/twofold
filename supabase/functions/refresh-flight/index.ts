// User-triggered refresh for a single flight (e.g. the caller opens the live-tracking screen).
// Verifies couple membership via the user-scoped client first, then does everything else with
// the service role key since flights/flight_status_events have no client write policy.
//
// Dedup guard: if the row was refreshed less than 60 seconds ago, this returns the current row
// as-is without calling AeroAPI again — the thing that stops both partners opening the screen at
// the same moment from doubling API calls. Taken as a conditional update of last_refreshed_at, so
// it holds for callers that arrive together too (see the claim below).
//
// Requires an `Authorization: Bearer <user access token>` header (the caller's Supabase auth
// session).

import { createClient } from "jsr:@supabase/supabase-js@2";
import { userSession } from "../_shared/auth.ts";
import { enforceRateLimit } from "../_shared/rate-limit.ts";
import {
  AIRBORNE_STATUSES,
  type FlightRow,
  reconcileOverdueArrival,
  refreshOneFlight,
  syncLivePositionForFaFlightId,
} from "../_shared/flight-sync.ts";

const DEDUP_WINDOW_MS = 60 * 1000;
// Its own bucket, like every other endpoint's; see the call below.
const RATE_LIMIT = { bucket: "refresh-flight", limit: 60, window: "1 hour" };
const TERMINAL_STATUSES = ["arrived", "landed", "cancelled", "diverted"];

interface Input {
  flightId: string;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405 });
  }

  let input: Input;
  try {
    input = await req.json();
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 });
  }
  if (!input?.flightId || typeof input.flightId !== "string") {
    return Response.json({ error: "'flightId' is required" }, { status: 400 });
  }

  const { userClient, user } = await userSession(req);
  if (!user) {
    return Response.json({ error: "Not authenticated" }, { status: 401 });
  }

  // RLS on `flights` already scopes select() to couple members, so a row coming back at all
  // proves membership — this doubles as the 403 check.
  const { data: visibleFlight, error: visibleErr } = await userClient
    .from("flights")
    .select("id")
    .eq("id", input.flightId)
    .maybeSingle();
  if (visibleErr || !visibleFlight) {
    return Response.json({ error: "Flight not found" }, { status: 403 });
  }

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: flightRow, error: flightErr } = await serviceClient
    .from("flights")
    .select("*")
    .eq("id", input.flightId)
    .single();
  if (flightErr || !flightRow) {
    return Response.json({ error: "Flight not found" }, { status: 404 });
  }

  // Not tracked anymore (archived post-arrival, or its couple dissolved — see leave_couple in
  // 20260723000000) — a stale client holding this flight ID shouldn't be able to resurrect an
  // AeroAPI call for it. RLS already lets a couple member view the row's history regardless of
  // couple status (see flights_select_members), so this endpoint being reachable at all doesn't
  // imply it should still poll.
  if (!flightRow.tracking_enabled) {
    return Response.json({ flight: flightRow });
  }

  // Already done — no point asking AeroAPI for more (and, critically, if reconcileOverdueArrival
  // forced this to "arrived" itself without ever getting a real actual_in from the provider, a
  // *later* genuine AeroAPI response with actual_in set would otherwise re-fire a second
  // "arrived at gate" push — diffEvents' actual_in check only knows about the existing row's
  // actual_in, not that reconcileOverdueArrival already declared it arrived by another means).
  if (TERMINAL_STATUSES.includes(flightRow.status)) {
    try {
      await reconcileOverdueArrival(serviceClient, flightRow as FlightRow, Date.now());
    } catch (err) {
      console.error("[refresh-flight] reconcileOverdueArrival failed:", (err as Error).message);
    }
    const { data: current } = await serviceClient.from("flights").select("*").eq("id", input.flightId).single();
    return Response.json({ flight: current ?? flightRow });
  }

  // Per account, across every flight. The dedup below bounds one flight to a lookup a minute, but
  // not one account: a couple with several tracked flights, or a client asking in a loop, could
  // still have every one of them looked up every minute, on top of the cron already polling them.
  // 60 an hour is far past what the app asks — once per open of the tracking screen — and placed
  // here, after the checks that answer without AeroAPI, so a refresh that could never reach it
  // spends no budget.
  const limited = await enforceRateLimit(userClient, RATE_LIMIT, { failClosed: true });
  if (limited) return limited;

  // The dedup is a claim, not a read. It used to read last_refreshed_at above and call AeroAPI if
  // it was old, so every caller holding the same stale read passed it — five refreshes arriving
  // together made five lookups. Stamping the row only where the stamp is still old is one
  // statement Postgres serialises per row: the first caller's update matches and takes the
  // refresh, and every caller after it finds a fresh stamp and matches nothing.
  //
  // The claimed row, with its new stamp, is what goes on to `refreshOneFlight`, because syncFlight
  // writes only if the stamp is still the one it was handed (DB-6). A failed claim is read as not
  // claimed: the cost of being wrong that way is one skipped refresh, not one extra lookup.
  const nowIso = new Date().toISOString();
  const staleBefore = new Date(Date.now() - DEDUP_WINDOW_MS).toISOString();
  const { data: claimedRows, error: claimErr } = await serviceClient
    .from("flights")
    .update({ last_refreshed_at: nowIso })
    .eq("id", input.flightId)
    .eq("tracking_enabled", true)
    .or(`last_refreshed_at.is.null,last_refreshed_at.lt.${staleBefore}`)
    .select("*");
  if (claimErr) console.error("[refresh-flight] failed to claim the refresh:", claimErr.message);
  const claimed = (claimedRows?.[0] ?? null) as FlightRow | null;

  if (!claimed) {
    // Still worth reconciling even without a fresh AeroAPI call — someone pulling to refresh on
    // a flight the provider has gone silent on should see it self-heal immediately rather than
    // waiting for the next 5-minute cron tick.
    try {
      await reconcileOverdueArrival(serviceClient, flightRow as FlightRow, Date.now());
    } catch (err) {
      console.error("[refresh-flight] reconcileOverdueArrival failed:", (err as Error).message);
    }
    const { data: current } = await serviceClient.from("flights").select("*").eq("id", input.flightId).single();
    return Response.json({ flight: current ?? flightRow });
  }

  try {
    const updated = await refreshOneFlight(serviceClient, claimed, "refresh-flight");
    if (updated) {
      try {
        await reconcileOverdueArrival(serviceClient, updated, Date.now());
      } catch (err) {
        console.error("[refresh-flight] reconcileOverdueArrival failed:", (err as Error).message);
      }

      // Immediate, user-triggered live-position refresh — bypasses the 60s DEDUP_WINDOW_MS above
      // (that window governs AeroAPI schedule-call cost, not this), since
      // syncLivePositionForFaFlightId's own ~55s cache TTL already caps real mirror calls even
      // under both partners pulling to refresh at once.
      if (updated.fa_flight_id && AIRBORNE_STATUSES.includes(updated.status)) {
        try {
          const candidates = [updated.atc_ident, updated.flight_number_icao].filter((v): v is string => Boolean(v));
          await syncLivePositionForFaFlightId(serviceClient, updated.fa_flight_id, candidates);
        } catch (err) {
          console.error("[refresh-flight] syncLivePositionForFaFlightId failed:", (err as Error).message);
        }
      }
    }
    const { data: finalRow } = await serviceClient.from("flights").select("*").eq("id", input.flightId).single();
    return Response.json({ flight: finalRow ?? updated ?? flightRow });
  } catch (err) {
    console.error("[refresh-flight] refresh failed:", (err as Error).message);
    return Response.json({ error: "Refresh failed, please try again" }, { status: 502 });
  }
});

/* To invoke locally:

  1. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  2. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/refresh-flight' \
    --header 'apiKey: sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH' \
    --header 'Authorization: Bearer <user-access-token>' \
    --data '{"flightId":"00000000-0000-0000-0000-000000000000"}'

*/
