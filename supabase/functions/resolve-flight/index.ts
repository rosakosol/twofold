// Looks up candidate flights from AeroAPI (FlightAware) so the client can show the caller a
// short list of matches to confirm before add-flight actually starts tracking one. Supports two
// modes: a flight-number lookup (e.g. "QF35" on a given date) and a route search (origin +
// destination + date) for travelers who don't know their flight number. Read-only — no DB writes.
//
// Requires an `Authorization: Bearer <user access token>` header (the caller's Supabase auth
// session) so we can verify they belong to an active couple before spending an AeroAPI call.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { type AeroFlight, resolveFlightByIdent, searchRoute } from "../_shared/aeroapi.ts";
import { lookupAirlineName } from "../_shared/airlines.ts";
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
//
// AeroAPI rejects the request outright ("invalid end bound: time is too far into future (limit:
// 2 days)") if `end` is more than ~2 days past the moment of the request — regardless of how far
// out the caller's requested date is. Clamp both bounds into that window instead of letting a
// legitimately-future search (e.g. searching a flight number for next week) 400 the whole
// lookup; a few minutes of slack below the hard cap guards against clock skew between here and
// AeroAPI. A search clamped this way may simply come back with fewer/no matches for a date
// that's genuinely beyond what AeroAPI can predict yet — that's a real "no flights found" state,
// not a bug.
function dateWindow(date: string): { startISO: string; endISO: string } {
  const target = new Date(`${date}T00:00:00Z`);
  let end = new Date(target.getTime());
  end.setUTCDate(end.getUTCDate() + 2);
  let start = new Date(target.getTime());
  start.setUTCDate(start.getUTCDate() - 1);

  const maxEnd = new Date();
  maxEnd.setUTCDate(maxEnd.getUTCDate() + 2);
  maxEnd.setUTCMinutes(maxEnd.getUTCMinutes() - 5);

  if (end.getTime() > maxEnd.getTime()) {
    // Shift the whole window back in time rather than just pinning `end` to the ceiling —
    // pinning alone can collapse `start` to the same instant as `end` (or leave it past `end`)
    // once clamped, and a zero/negative-width range is its own kind of malformed request as far
    // as AeroAPI's own schema validation is concerned ("type is incorrect"). Preserving the
    // original 3-day width keeps the request shape identical to the un-clamped case.
    const shiftMs = end.getTime() - maxEnd.getTime();
    end = maxEnd;
    start = new Date(start.getTime() - shiftMs);
  }

  // AeroAPI's parser has rejected a `.toISOString()` timestamp's trailing milliseconds before
  // ("type is incorrect") — strip them defensively; AeroAPI's own documented examples never
  // include a fractional-seconds component.
  return { startISO: toAeroTimestamp(start), endISO: toAeroTimestamp(end) };
}

function toAeroTimestamp(date: Date): string {
  return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}

// `iso` is a UTC instant from AeroAPI; `date` is the calendar date the caller searched for,
// meant as "departure date at the origin airport" — comparing UTC-sliced date strings directly
// against that is wrong for roughly half of all flights (any origin west of UTC with a morning
// departure, or east of UTC with a late-evening one, lands on the *other* UTC day). Converts the
// instant into the origin airport's own IANA timezone before comparing, so "today" means today
// at the airport the flight actually leaves from.
function isSameLocalDay(iso: string | null | undefined, date: string, timeZone: string | null | undefined): boolean {
  if (!iso) return false;
  const zone = timeZone || "UTC";
  try {
    const parts = new Intl.DateTimeFormat("en-CA", {
      timeZone: zone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).formatToParts(new Date(iso));
    const year = parts.find((p) => p.type === "year")?.value;
    const month = parts.find((p) => p.type === "month")?.value;
    const day = parts.find((p) => p.type === "day")?.value;
    if (!year || !month || !day) return iso.slice(0, 10) === date;
    return `${year}-${month}-${day}` === date;
  } catch {
    // Unrecognized/malformed IANA identifier — fall back to the naive UTC comparison rather
    // than throwing away an otherwise-valid flight.
    return iso.slice(0, 10) === date;
  }
}

function toCandidate(f: AeroFlight) {
  return {
    faFlightId: f.fa_flight_id,
    identIata: f.ident_iata ?? null,
    identIcao: f.ident_icao ?? null,
    operatorName: lookupAirlineName(f.operator_iata, f.operator_icao, f.operator),
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
      const sameDay = results.filter((f) => isSameLocalDay(f.scheduled_out, input.date, f.origin?.timezone));
      flights = sameDay.length > 0 ? sameDay : results;
      if (input.originIata) {
        flights = flights.filter((f) => f.origin?.code_iata === input.originIata || f.origin?.code === input.originIata);
      }
      console.log(`[resolve-flight] number ${input.flightNumber} on ${input.date}: aeroapi returned ${results.length} total, ${sameDay.length} same-day, ${flights.length} after origin filter`);
    } else {
      const results = await searchRoute(input.originIata, input.destinationIata);
      // AeroAPI's route search has no date param of its own — the date filter is applied here,
      // client-side. Same fallback as number mode: prefer an exact same-day match, but don't
      // return zero results just because the origin's timezone data was missing/imprecise and
      // the strict same-day check happened to exclude a real, otherwise-matching flight.
      const sameDay = results.filter((f) => isSameLocalDay(f.scheduled_out, input.date, f.origin?.timezone));
      flights = sameDay.length > 0 ? sameDay : results;
      console.log(`[resolve-flight] route ${input.originIata}->${input.destinationIata} on ${input.date}: aeroapi returned ${results.length} total, ${sameDay.length} same-day`);
    }

    return Response.json({ candidates: flights.map(toCandidate) });
  } catch (err) {
    const message = (err as Error).message;
    console.error("[resolve-flight] AeroAPI lookup failed:", message);
    // Relay AeroAPI's own complaint when we have one (e.g. "Invalid API key", a malformed-query
    // rejection, rate-limiting) — it's not secret, and it's the difference between "no matching
    // flights" and "the request itself was rejected," which otherwise looks identical to the
    // user as a generic failure.
    return Response.json({ error: `Flight lookup failed: ${message}` }, { status: 502 });
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
