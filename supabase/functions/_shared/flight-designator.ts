// Flight designators ("QF35"): parsing what the caller typed, and recognising it in AeroAPI's
// answers. Split out of resolve-flight/index.ts so it can be tested — that file has a top-level
// Deno.serve, so importing anything from it starts a server. See flight-designator.test.ts.

import { airlineCodesMatch } from "./airlines.ts";
import type { AeroScheduledFlight } from "./aeroapi.ts";

// Splits a flight designator ("QF35", "qf035") into the airline code + numeric flight number
// /schedules' own `airline`/`flight_number` query params want. Returns null on anything that
// doesn't look like <letters><digits> — callers skip the /schedules lookup entirely rather than
// guess, since an unfiltered /schedules call (no airline/flight_number) would return every
// scheduled flight globally for the date window.
export function splitFlightDesignator(raw: string): { airline: string; flightNumber: number } | null {
  const match = raw.trim().toUpperCase().match(/^([A-Z]{2,3})0*(\d+)$/);
  if (!match) return null;
  return { airline: match[1], flightNumber: Number(match[2]) };
}

// Whether a resolved flight's own ident is the same designator the caller typed. Compared
// numerically (and via airlineCodesMatch) rather than as strings, so "QF035" vs "QF35" and
// IATA-vs-ICAO airline codes don't read as a mismatch and invent a bogus marketing number.
export function identIsSearchedDesignator(
  ident: string | null | undefined,
  designator: { airline: string; flightNumber: number },
): boolean {
  if (!ident) return false;
  const parsed = splitFlightDesignator(ident);
  if (!parsed) return false;
  return parsed.flightNumber === designator.flightNumber && airlineCodesMatch(parsed.airline, designator.airline);
}

// Whether a /schedules row is listed under the number the caller typed.
//
// /schedules includes codeshares unless told otherwise, and for a query by airline and number it
// returns the searched flight plus a row per partner airline marketing a seat on it: each row's
// `ident` is the partner's number and `actual_ident` is the searched one. Searching QF35 listed
// those partner numbers too — above QF35 itself — though none of them is on the traveller's ticket.
//
// Keeping only rows whose own ident is the searched designator removes them, and still serves
// someone who typed a partner's number: that row's own ident is exactly what they typed, so it is
// kept, and its `actual_ident` still marks it a codeshare. Not `include_codeshares=false`, which
// would drop that row too.
export function isSearchedScheduleRow(
  s: Pick<AeroScheduledFlight, "ident" | "ident_iata" | "ident_icao">,
  designator: { airline: string; flightNumber: number },
): boolean {
  return [s.ident_iata, s.ident_icao, s.ident].some((ident) => identIsSearchedDesignator(ident, designator));
}
