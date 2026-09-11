// User-triggered, on-demand 60-day delay-performance lookup for one tracked flight's designator
// (e.g. "UAE1") — called when the caller opens that flight's detail screen, not proactively by
// any cron. Verifies couple membership via the user-scoped client first, same pattern as
// refresh-flight, then does the real work with the service role key.
//
// Requires an `Authorization: Bearer <user access token>` header (the caller's Supabase auth
// session), and a couple on Premium — see the tier check below. Requires the AeroAPI account to
// be on Standard tier or above — Personal tier doesn't
// include historical data access at all, and AeroAPI will error accordingly; that error just
// propagates as a non-2xx response, which the caller already treats as "don't show this card."

import { createClient } from "jsr:@supabase/supabase-js@2";
import { computeDelayStats } from "../_shared/delay-stats.ts";

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
  // proves membership — this doubles as the 403 check, same as refresh-flight.
  const { data: visibleFlight, error: visibleErr } = await userClient
    .from("flights")
    .select("id, couple_id")
    .eq("id", input.flightId)
    .maybeSingle();
  if (visibleErr || !visibleFlight) {
    return Response.json({ error: "Flight not found" }, { status: 403 });
  }

  // Delay analysis is a Premium card, and until now that was enforced only by
  // `FlightTrackingView` declining to call this. Every other Premium gate in the app has a
  // server behind it — `start_deck_session` and `start_sudoku_session` both check the couple's
  // tier — and this one needed it most: the work below is the most expensive request the app
  // makes, ten chunked `/history/flights` calls per designator. A client that simply called it
  // anyway got Premium data and spent real money doing so.
  //
  // Via `flight_allowance` rather than reading profiles here. It is a public, membership-checked
  // function that already resolves the couple's effective tier through
  // `private.couple_effective_tier` — a schema PostgREST does not serve, so there is no way to
  // ask for the tier directly. Its name is about flights rather than tiers, which is the one
  // awkward part; re-deriving the rule here would be the worse trade, since "which tier is this
  // couple on" would then live in a third place and be free to disagree with the other two.
  //
  // Called with the *user* client so the membership check inside it applies to the caller.
  const { data: allowance, error: allowanceErr } = await userClient
    .rpc("flight_allowance", { p_couple_id: visibleFlight.couple_id });
  if (allowanceErr) {
    console.error("[flight-delay-stats] could not resolve tier:", allowanceErr.message);
    return Response.json({ error: "Could not verify your plan" }, { status: 500 });
  }
  if (allowance?.tier !== "premium") {
    // 403 rather than an empty result: the caller's own UI does not offer this on Plus, so
    // reaching here at all means something is asking for what it was not offered, and saying so
    // plainly is better than silently returning nothing that looks like a provider outage.
    return Response.json(
      { error: "Delay analysis is included with Twofold Premium.", code: "premium_required" },
      { status: 403 },
    );
  }

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: flightRow, error: flightErr } = await serviceClient
    .from("flights")
    .select("flight_number_icao, flight_number_iata")
    .eq("id", input.flightId)
    .single();
  if (flightErr || !flightRow) {
    return Response.json({ error: "Flight not found" }, { status: 404 });
  }

  const ident = flightRow.flight_number_icao ?? flightRow.flight_number_iata;
  if (!ident) {
    return Response.json({ error: "This flight has no flight number to look up" }, { status: 422 });
  }

  try {
    const stats = await computeDelayStats(serviceClient, ident);
    return Response.json(stats);
  } catch (err) {
    console.error(`[flight-delay-stats] computeDelayStats failed for ${ident}:`, (err as Error).message);
    return Response.json({ error: "Failed to compute delay stats" }, { status: 502 });
  }
});

/* To invoke locally:

  1. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  2. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/flight-delay-stats' \
    --header 'apiKey: sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH' \
    --header 'Authorization: Bearer <user-access-token>' \
    --data '{"flightId":"00000000-0000-0000-0000-000000000000"}'

*/
