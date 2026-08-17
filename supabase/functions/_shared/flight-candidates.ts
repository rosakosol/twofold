// The Candidate shape resolve-flight returns, and the dedup that decides which of AeroAPI's
// several answers for one search actually reach the user.
//
// Extracted from resolve-flight/index.ts so the dedup can be tested — that file has a top-level
// Deno.serve, so importing anything from it starts a server. See flight-candidates.test.ts.

import { type deriveFlightStatus } from "./flight-status.ts";

// Response shape both AeroFlight (/flights/{ident}, /flights/search) and AeroScheduledFlight
// (/schedules) normalize into — the two sources have genuinely different field shapes (nested
// origin/destination objects with timezone/name/city vs. flat code strings; live-tracking fields
// vs. none at all), so each gets its own mapper into this common shape rather than one trying to
// pretend to be the other.
export interface Candidate {
  faFlightId: string | null;
  identIata: string | null;
  identIcao: string | null;
  operatorName: string | null;
  operatorIata: string | null;
  flightNumberIata: string | null;
  aircraftType: string | null;
  origin: { iata: string | null; icao: string | null; name: string | null; city: string | null; timezone: string | null } | null;
  destination: { iata: string | null; icao: string | null; name: string | null; city: string | null; timezone: string | null } | null;
  scheduledOut: string | null;
  scheduledIn: string | null;
  status: ReturnType<typeof deriveFlightStatus>;
  cancelled: boolean;
  diverted: boolean;
  isCodeshare: boolean;
  // The designator the caller actually typed, when it differs from this flight's own operating
  // ident — i.e. they searched a codeshare number (CX6104) and AeroAPI answered with the flight
  // that operates it (CA104). Null whenever they searched the operating number directly, and for
  // route mode, where there's no searched designator at all. The client shows this as the headline
  // number, because it's what's on their boarding pass.
  marketingIdent: string | null;
  // false only for a /schedules result whose fa_flight_id came back null — a flight that's on
  // the airline's published schedule but that FlightAware hasn't assigned a concrete trackable
  // instance to yet (per AeroAPI's own docs, this normally resolves a few days before departure).
  // The client should let the caller see this candidate but not attempt to add-flight it yet.
  isTrackable: boolean;
}

// Merges live-tracking and schedule-sourced candidates for the same search, and collapses the
// duplicates AeroAPI returns for a single flight.
//
// Dedup is on the flight's *physical* identity — number, route and scheduled departure instant —
// not on `fa_flight_id`. Keying on fa_flight_id alone was the bug: AeroAPI hands back several
// records for one real flight, each with its own id (the same shape as the FJ810 case noted in
// `filterPreferringSameDay`, where one designator search returned three near-identical instances).
// Searching CX6104 produced two result rows that were identical in every visible respect — same
// number, same operator, same route, same times — with no way for anyone to tell which to pick.
//
// Safe because those four things together can't describe two different flights: one aircraft
// cannot leave the same airport for the same airport under the same number at the same instant.
// Distinct instances of a daily service still differ by `scheduledOut`, so they survive — which is
// the whole point, since picking your date out of a list is a real part of this flow.
//
// Falls back to fa_flight_id only when there's no scheduled departure to key on (a flight AeroAPI
// has assigned no timestamps to at all), since without one the physical key would collapse
// genuinely different flights together.
function candidateKey(c: Candidate): string {
  if (!c.scheduledOut) return c.faFlightId ?? `${c.identIata ?? c.identIcao ?? ""}:no-schedule`;
  const ident = (c.identIata ?? c.identIcao ?? "").toUpperCase();
  const origin = (c.origin?.iata ?? c.origin?.icao ?? "").toUpperCase();
  const destination = (c.destination?.iata ?? c.destination?.icao ?? "").toUpperCase();
  return `${ident}|${origin}|${destination}|${c.scheduledOut}`;
}

// How much a candidate is actually worth keeping when two describe the same flight. Trackability
// dominates: a candidate with no fa_flight_id can't be added yet at all, so it must never win over
// one that can. Live signal breaks the remaining ties — a record AeroAPI has already attached real
// departure/arrival data to is the one that will keep updating.
function candidateRichness(c: Candidate): number {
  let score = 0;
  if (c.isTrackable && c.faFlightId) score += 8;
  if (c.status && c.status !== "scheduled") score += 4;
  if (c.scheduledIn) score += 2;
  if (c.aircraftType) score += 1;
  return score;
}

export function mergeCandidates(primary: Candidate[], extra: Candidate[]): Candidate[] {
  // `primary` (live) is listed first so it wins ties against `extra` (schedule-sourced), which
  // carries strictly less data — the original reason this function existed.
  const byKey = new Map<string, Candidate>();
  for (const c of [...primary, ...extra]) {
    const k = candidateKey(c);
    const existing = byKey.get(k);
    if (!existing || candidateRichness(c) > candidateRichness(existing)) {
      byKey.set(k, c);
    }
  }
  return [...byKey.values()];
}
