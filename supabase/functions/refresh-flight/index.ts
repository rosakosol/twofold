// User-triggered refresh for a single flight (e.g. the caller opens the live-tracking screen).
// Verifies couple membership via the user-scoped client first, then does everything else with
// the service role key since flights/flight_status_events have no client write policy.
//
// Dedup guard: if the row was refreshed less than 60 seconds ago, this returns the current row
// as-is without calling AeroAPI again — the thing that stops both partners opening the screen at
// the same moment from doubling API calls.
//
// Requires an `Authorization: Bearer <user access token>` header (the caller's Supabase auth
// session).

import { createClient } from "jsr:@supabase/supabase-js@2";
import { type FlightRow, reconcileOverdueArrival, refreshOneFlight } from "../_shared/flight-sync.ts";

const DEDUP_WINDOW_MS = 60 * 1000;

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

  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
  );

  const { data: { user } } = await userClient.auth.getUser();
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

  const lastRefreshedAt = flightRow.last_refreshed_at ? new Date(flightRow.last_refreshed_at).getTime() : 0;
  if (Date.now() - lastRefreshedAt < DEDUP_WINDOW_MS) {
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
    const updated = await refreshOneFlight(serviceClient, flightRow);
    if (updated) {
      try {
        await reconcileOverdueArrival(serviceClient, updated, Date.now());
      } catch (err) {
        console.error("[refresh-flight] reconcileOverdueArrival failed:", (err as Error).message);
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
