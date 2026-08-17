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

Deno.test("empty in, empty out", () => {
  assertEquals(mergeCandidates([], []).length, 0);
});
