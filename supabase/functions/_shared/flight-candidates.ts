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
// AeroAPI produces two *different* kinds of duplicate for one search, and neither key catches
// both — which is why the collapse runs in two passes rather than on one composite key.
//
// The physical key — number, route and scheduled departure instant. Safe because those together
// can't describe two different flights: one aircraft cannot leave the same airport for the same
// airport under the same number at the same instant. This catches the case where AeroAPI has
// issued several records for one real flight, each with its own fa_flight_id (searching CX6104
// returned two rows identical in every visible respect — same number, operator, route and times —
// with no way for anyone to tell which to pick; the FJ810 case in `filterPreferringSameDay` is
// the same shape). Distinct instances of a daily service still differ by `scheduledOut`, so they
// survive, which is the point — picking your date out of a list is a real part of this flow.
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

// The fa_flight_id key, which the physical key cannot stand in for. One fa_flight_id is one
// aircraft movement, and AeroAPI returns it once per *marketing* designator — so a single search
// comes back as a row per codeshare partner, every one of them the same seat on the same plane.
// Their idents differ by definition (SQ208, AI8201, SK8066, LH9761, TK9303, VA5508, ET1302 — the
// reported case, seven rows for one Melbourne–Singapore departure), so the physical key sees seven
// distinct flights. To the traveller they are one flight listed seven times, and worse, six of
// them are numbers that aren't on their ticket.
//
// This is a regression surface, not an oversight: number mode used to filter results down to the
// operating carrier, which discarded these as a side effect. That filter was removed so a
// codeshare number would stop returning "no flights found" (see isOperatingCarrier), and the
// duplicates it had been hiding came back with it.
function movementKey(c: Candidate): string | null {
  return c.faFlightId;
}

// How much a candidate is actually worth keeping when two describe the same flight. Trackability
// dominates: a candidate with no fa_flight_id can't be added yet at all, so it must never win over
// one that can. Live signal breaks the remaining ties — a record AeroAPI has already attached real
// departure/arrival data to is the one that will keep updating.
function candidateRichness(c: Candidate): number {
  let score = 0;
  // Outranks everything, because it isn't a data-quality question. A null marketingIdent means
  // this row's own ident is the designator the caller typed (see marketingIdentFor). When the
  // codeshare rows above collapse, that is the row to keep: its operator name and logo are the
  // airline on their ticket, and the alternative is telling someone who searched SQ208 that they
  // are flying Ethiopian. Null for every row in route mode, where there's no searched designator,
  // so it simply doesn't discriminate there.
  if (c.marketingIdent === null) score += 16;
  if (c.isTrackable && c.faFlightId) score += 8;
  if (c.status && c.status !== "scheduled") score += 4;
  if (c.scheduledIn) score += 2;
  if (c.aircraftType) score += 1;
  return score;
}

// Collapses by one key, keeping the richest of each group. Candidates the key doesn't apply to
// pass through untouched. Result order follows first appearance, so `primary` keeps outranking
// `extra` positionally even when a later candidate wins its group on richness.
function collapseBy(candidates: Candidate[], key: (c: Candidate) => string | null): Candidate[] {
  const groups = new Map<string, { at: number; candidate: Candidate }>();
  const passthrough: { at: number; candidate: Candidate }[] = [];
  candidates.forEach((candidate, at) => {
    const k = key(candidate);
    if (k === null) {
      passthrough.push({ at, candidate });
      return;
    }
    const existing = groups.get(k);
    if (!existing || candidateRichness(candidate) > candidateRichness(existing.candidate)) {
      groups.set(k, { at: existing?.at ?? at, candidate });
    }
  });
  return [...groups.values(), ...passthrough]
    .sort((a, b) => a.at - b.at)
    .map((entry) => entry.candidate);
}

export function mergeCandidates(primary: Candidate[], extra: Candidate[]): Candidate[] {
  // `primary` (live) is listed first so it wins ties against `extra` (schedule-sourced), which
  // carries strictly less data — the original reason this function existed.
  //
  // Movement first: it groups rows the physical key would keep apart, and collapsing them early
  // means the physical pass sees one row per real flight instead of one per codeshare partner.
  return collapseBy(collapseBy([...primary, ...extra], movementKey), candidateKey);
}
