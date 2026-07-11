// Looks up candidate flights from AeroAPI (FlightAware) so the client can show the caller a
// short list of matches to confirm before add-flight actually starts tracking one. Supports two
// modes: a flight-number lookup (e.g. "QF35" on a given date) and a route search (origin +
// destination + date) for travelers who don't know their flight number. Read-only — no DB writes.
//
// Requires an `Authorization: Bearer <user access token>` header (the caller's Supabase auth
// session) so we can verify they belong to an active couple before spending an AeroAPI call.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { type AeroFlight, resolveFlightByIdent, searchRoute } from "../_shared/aeroapi.ts";
import { deriveFlightStatus } from "../_shared/flight-status.ts";

interface NumberModeInput {
  mode: "number";
  flightNumber: string;
  date: string; // YYYY-MM-DD
  originIata?: string;
}

interface RouteModeInput {
  mode: "route";
  originIata: string;
  destinationIata: string;
  date: string; // YYYY-MM-DD
}

type Input = NumberModeInput | RouteModeInput;

function isValidDate(date: unknown): date is string {
  return typeof date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(date);
}

// AeroAPI's ident lookup wants an ISO8601 start/end window; give it a couple of days either side
// of the requested date to comfortably catch overnight departures/arrivals.
function dateWindow(date: string): { startISO: string; endISO: string } {
  const start = new Date(`${date}T00:00:00Z`);
  const end = new Date(start.getTime());
  end.setUTCDate(end.getUTCDate() + 2);
  const rangeStart = new Date(start.getTime());
  rangeStart.setUTCDate(rangeStart.getUTCDate() - 1);
  return { startISO: rangeStart.toISOString(), endISO: end.toISOString() };
}

function isSameLocalDay(iso: string | null | undefined, date: string): boolean {
  if (!iso) return false;
  return iso.slice(0, 10) === date;
}

function toCandidate(f: AeroFlight) {
  return {
    faFlightId: f.fa_flight_id,
    identIata: f.ident_iata ?? null,
    identIcao: f.ident_icao ?? null,
    operatorName: null, // not available on this endpoint — see _shared/flight-sync.ts's mapping comment
    operatorIata: f.operator_iata ?? f.operator_icao ?? f.operator ?? null,
    flightNumberIata: f.ident_iata ?? f.ident ?? null,
    aircraftType: f.aircraft_type ?? null,
    origin: f.origin
      ? {
        iata: f.origin.code_iata ?? null,
        icao: f.origin.code_icao ?? null,
        name: f.origin.name ?? null,
        city: f.origin.city ?? null,
        timezone: f.origin.timezone ?? null,
      }
      : null,
    destination: f.destination
      ? {
        iata: f.destination.code_iata ?? null,
        icao: f.destination.code_icao ?? null,
        name: f.destination.name ?? null,
        city: f.destination.city ?? null,
        timezone: f.destination.timezone ?? null,
      }
      : null,
    scheduledOut: f.scheduled_out ?? null,
    scheduledIn: f.scheduled_in ?? null,
    status: deriveFlightStatus(f),
    cancelled: Boolean(f.cancelled),
    diverted: Boolean(f.diverted),
    isCodeshare: (f.codeshares?.length ?? 0) > 0,
  };
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

  if (input?.mode !== "number" && input?.mode !== "route") {
    return Response.json({ error: "'mode' must be 'number' or 'route'" }, { status: 400 });
  }
  if (!isValidDate(input.date)) {
    return Response.json({ error: "'date' must be YYYY-MM-DD" }, { status: 400 });
  }
  if (input.mode === "number" && (!input.flightNumber || typeof input.flightNumber !== "string")) {
    return Response.json({ error: "'flightNumber' is required for mode 'number'" }, { status: 400 });
  }
  if (input.mode === "route" && (!input.originIata || !input.destinationIata)) {
    return Response.json({ error: "'originIata' and 'destinationIata' are required for mode 'route'" }, { status: 400 });
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

  const { data: couple, error: coupleErr } = await userClient
    .from("couples")
    .select("id")
    .or(`partner_a_id.eq.${user.id},partner_b_id.eq.${user.id}`)
    .eq("status", "active")
    .maybeSingle();
  if (coupleErr || !couple) {
    return Response.json({ error: "No active couple for this user" }, { status: 403 });
  }

  try {
    let flights: AeroFlight[] = [];

    if (input.mode === "number") {
      const { startISO, endISO } = dateWindow(input.date);
      const results = await resolveFlightByIdent(input.flightNumber, { startISO, endISO, identType: "designator" });
      // Prefer same-day matches when the ident resolves to several scheduled instances; fall
      // back to the full result set if none match exactly (e.g. timezone edge cases).
      const sameDay = results.filter((f) => isSameLocalDay(f.scheduled_out, input.date));
      flights = sameDay.length > 0 ? sameDay : results;
      if (input.originIata) {
        flights = flights.filter((f) => f.origin?.code_iata === input.originIata || f.origin?.code === input.originIata);
      }
    } else {
      const results = await searchRoute(input.originIata, input.destinationIata);
      flights = results.filter((f) => isSameLocalDay(f.scheduled_out, input.date));
    }

    return Response.json({ candidates: flights.map(toCandidate) });
  } catch (err) {
    console.error("[resolve-flight] AeroAPI lookup failed:", (err as Error).message);
    return Response.json({ error: "Flight lookup failed, please try again" }, { status: 502 });
  }
});

/* To invoke locally:

  1. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  2. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/resolve-flight' \
    --header 'apiKey: sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH' \
    --header 'Authorization: Bearer <user-access-token>' \
    --data '{"mode":"number","flightNumber":"QF35","date":"2026-09-14"}'

*/
