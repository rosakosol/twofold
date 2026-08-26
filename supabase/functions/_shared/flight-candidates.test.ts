// Tests for how AeroAPI's several answers to one search get collapsed into the list a person
// actually chooses from.
//
// The bug this pins: searching CX6104 returned two result rows that were identical in every
// visible respect — same number, same operator, same route, same times — because dedup keyed on
// `fa_flight_id` and AeroAPI had issued two records for the one real flight. Nobody could tell
// which to pick, and picking the wrong one is not recoverable from the UI.
//
// Run with: deno test supabase/functions/_shared/flight-candidates.test.ts

import { assertEquals } from "jsr:@std/assert";
import { type Candidate, mergeCandidates } from "./flight-candidates.ts";

function candidate(overrides: Partial<Candidate> = {}): Candidate {
  return {
    faFlightId: "FA1",
    identIata: "CA104",
    identIcao: null,
    operatorName: "Air China",
    operatorIata: "CA",
    flightNumberIata: "CA104",
    aircraftType: null,
    origin: { iata: "HKG", icao: "VHHH", name: null, city: "Hong Kong", timezone: "Asia/Hong_Kong" },
    destination: { iata: "TSN", icao: "ZBTJ", name: null, city: "Tianjin", timezone: "Asia/Shanghai" },
    scheduledOut: "2026-08-17T06:50:00Z",
    scheduledIn: "2026-08-17T10:15:00Z",
    status: "scheduled",
    cancelled: false,
    diverted: false,
    isCodeshare: false,
    marketingIdent: null,
    isTrackable: true,
    ...overrides,
  } as Candidate;
}

// The reported case, exactly: one physical flight, two AeroAPI records.
Deno.test("collapses two records for the same flight that differ only by fa_flight_id", () => {
  const merged = mergeCandidates(
    [candidate({ faFlightId: "FA1" }), candidate({ faFlightId: "FA2" })],
    [],
  );
  assertEquals(merged.length, 1);
});

Deno.test("keeps genuinely different departures of the same daily service", () => {
  const merged = mergeCandidates([
    candidate({ faFlightId: "FA1", scheduledOut: "2026-08-17T06:50:00Z" }),
    candidate({ faFlightId: "FA2", scheduledOut: "2026-08-18T06:50:00Z" }),
    candidate({ faFlightId: "FA3", scheduledOut: "2026-08-19T06:50:00Z" }),
  ], []);
  assertEquals(merged.length, 3);
});

Deno.test("keeps different flight numbers on the same route and time", () => {
  const merged = mergeCandidates([
    candidate({ faFlightId: "FA1", identIata: "CA104" }),
    candidate({ faFlightId: "FA2", identIata: "CA106" }),
  ], []);
  assertEquals(merged.length, 2);
});

Deno.test("keeps the same number flown on a different route", () => {
  const merged = mergeCandidates([
    candidate({ faFlightId: "FA1" }),
    candidate({
      faFlightId: "FA2",
      destination: { iata: "PEK", icao: "ZBAA", name: null, city: "Beijing", timezone: "Asia/Shanghai" },
    }),
  ], []);
  assertEquals(merged.length, 2);
});

// A candidate with no fa_flight_id can't be handed to add-flight at all, so it must never win.
Deno.test("prefers the trackable record when duplicates disagree", () => {
  const merged = mergeCandidates([
    candidate({ faFlightId: null, isTrackable: false }),
    candidate({ faFlightId: "FA2", isTrackable: true }),
  ], []);
  assertEquals(merged.length, 1);
  assertEquals(merged[0].faFlightId, "FA2");
  assertEquals(merged[0].isTrackable, true);
});

Deno.test("prefers the record carrying live status over a bare scheduled one", () => {
  const merged = mergeCandidates([
    candidate({ faFlightId: "FA1", status: "scheduled" }),
    candidate({ faFlightId: "FA2", status: "in_air" }),
  ], []);
  assertEquals(merged.length, 1);
  assertEquals(merged[0].status, "in_air");
});

// The function's original job: live results outrank schedule-sourced ones for the same flight.
Deno.test("live candidates win over schedule-sourced duplicates", () => {
  const live = candidate({ faFlightId: "FA1", status: "in_air", aircraftType: "B77W" });
  const scheduled = candidate({ faFlightId: null, isTrackable: false, status: "scheduled", scheduledIn: null });
  const merged = mergeCandidates([live], [scheduled]);
  assertEquals(merged.length, 1);
  assertEquals(merged[0].aircraftType, "B77W");
});

Deno.test("a schedule-only flight AeroAPI can't track yet still comes through", () => {
  const merged = mergeCandidates([], [
    candidate({ faFlightId: null, isTrackable: false, scheduledOut: "2026-11-02T06:50:00Z" }),
  ]);
  assertEquals(merged.length, 1);
  assertEquals(merged[0].isTrackable, false);
});

// Without a scheduled departure there's no physical key to build, so these fall back to
// fa_flight_id rather than collapsing into each other.
Deno.test("timestamp-less flights are not collapsed together", () => {
  const merged = mergeCandidates([
    candidate({ faFlightId: "FA1", scheduledOut: null }),
    candidate({ faFlightId: "FA2", scheduledOut: null }),
  ], []);
  assertEquals(merged.length, 2);
});

Deno.test("ident and airport codes compare case-insensitively", () => {
  const merged = mergeCandidates([
    candidate({ faFlightId: "FA1", identIata: "CA104" }),
    candidate({
      faFlightId: "FA2",
      identIata: "ca104",
      origin: { iata: "hkg", icao: null, name: null, city: null, timezone: null },
    }),
  ], []);
  assertEquals(merged.length, 1);
});

Deno.test("the marketing designator survives the collapse", () => {
  const merged = mergeCandidates([
    candidate({ faFlightId: "FA1", marketingIdent: "CX6104", isCodeshare: true }),
    candidate({ faFlightId: "FA2", marketingIdent: "CX6104", isCodeshare: true, status: "in_air" }),
  ], []);
  assertEquals(merged.length, 1);
  assertEquals(merged[0].marketingIdent, "CX6104");
  assertEquals(merged[0].isCodeshare, true);
});

// The reported case, from the live response: searching SQ208 for tomorrow returned seven rows —
// one Melbourne–Singapore departure listed once per codeshare partner, all sharing AeroAPI's
// fa_flight_id "SIA208-1787640565-airline-337p". Only the searched row has a null marketingIdent;
// the rest carry "SQ208" as the number to display, so all seven rendered identically.
Deno.test("collapses one movement listed once per codeshare partner", () => {
  const movement = "SIA208-1787640565-airline-337p";
  const merged = mergeCandidates([
    candidate({ faFlightId: movement, identIata: "SQ208", operatorIata: "SQ", operatorName: "Singapore Airlines", marketingIdent: null }),
    candidate({ faFlightId: movement, identIata: "AI8201", operatorIata: "AI", operatorName: "Air India", marketingIdent: "SQ208" }),
    candidate({ faFlightId: movement, identIata: "SK8066", operatorIata: "SK", operatorName: "SAS", marketingIdent: "SQ208" }),
    candidate({ faFlightId: movement, identIata: "LH9761", operatorIata: "LH", operatorName: "Lufthansa", marketingIdent: "SQ208" }),
    candidate({ faFlightId: movement, identIata: "TK9303", operatorIata: "TK", operatorName: "Turkish Airlines", marketingIdent: "SQ208" }),
    candidate({ faFlightId: movement, identIata: "VA5508", operatorIata: "VA", operatorName: "Virgin Australia", marketingIdent: "SQ208" }),
    candidate({ faFlightId: movement, identIata: "ET1302", operatorIata: "ET", operatorName: "Ethiopian Airlines", marketingIdent: "SQ208" }),
  ], []);
  assertEquals(merged.length, 1);
  // Not just any survivor: the row the traveller searched for, so the card shows their airline.
  assertEquals(merged[0].identIata, "SQ208");
  assertEquals(merged[0].operatorName, "Singapore Airlines");
});

// Ordering must not decide it — AeroAPI has no obligation to list the operating row first.
Deno.test("the searched designator wins its movement whatever order it arrives in", () => {
  const merged = mergeCandidates([
    candidate({ faFlightId: "FA1", identIata: "ET1302", operatorIata: "ET", marketingIdent: "SQ208" }),
    candidate({ faFlightId: "FA1", identIata: "SQ208", operatorIata: "SQ", marketingIdent: null }),
  ], []);
  assertEquals(merged.length, 1);
  assertEquals(merged[0].identIata, "SQ208");
});

// When the search was itself a codeshare number, no row matches it and every marketingIdent is
// set — the collapse still has to happen, it just has no preference to express.
Deno.test("collapses a movement where no row carries the searched designator", () => {
  const merged = mergeCandidates([
    candidate({ faFlightId: "FA1", identIata: "CA104", marketingIdent: "CX6104", isCodeshare: true }),
    candidate({ faFlightId: "FA1", identIata: "MU7602", marketingIdent: "CX6104", isCodeshare: true }),
  ], []);
  assertEquals(merged.length, 1);
  assertEquals(merged[0].marketingIdent, "CX6104");
});

// Codeshare collapse must not reach across movements: two departures of the same service on one
// day are different flights, however many partners each is marketed by.
Deno.test("keeps separate movements that each carry codeshares", () => {
  const merged = mergeCandidates([
    candidate({ faFlightId: "FA-morning", identIata: "SQ208", scheduledOut: "2026-08-27T08:25:00Z", marketingIdent: null }),
    candidate({ faFlightId: "FA-morning", identIata: "ET1302", scheduledOut: "2026-08-27T08:25:00Z", marketingIdent: "SQ208" }),
    candidate({ faFlightId: "FA-evening", identIata: "SQ208", scheduledOut: "2026-08-27T20:10:00Z", marketingIdent: null }),
    candidate({ faFlightId: "FA-evening", identIata: "ET1302", scheduledOut: "2026-08-27T20:10:00Z", marketingIdent: "SQ208" }),
  ], []);
  assertEquals(merged.length, 2);
  assertEquals(merged.map((c) => c.scheduledOut), ["2026-08-27T08:25:00Z", "2026-08-27T20:10:00Z"]);
});

// A schedule-sourced row has no fa_flight_id to group on, so the movement pass must let it
// through untouched rather than treating "no id" as an id of its own.
Deno.test("untrackable rows survive the movement pass", () => {
  const merged = mergeCandidates([], [
    candidate({ faFlightId: null, isTrackable: false, identIata: "SQ208", scheduledOut: "2026-11-02T08:25:00Z" }),
    candidate({ faFlightId: null, isTrackable: false, identIata: "SQ212", scheduledOut: "2026-11-02T20:10:00Z" }),
  ]);
  assertEquals(merged.length, 2);
});

Deno.test("empty in, empty out", () => {
  assertEquals(mergeCandidates([], []).length, 0);
});
