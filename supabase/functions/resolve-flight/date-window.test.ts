// Which AeroAPI endpoint a flight search can reach is decided entirely by the requested date, and
// the three cases behave differently:
//
//   past    -> /flights/{ident} only reaches back ~10 days; older days need /history
//   present -> /flights/{ident} answers directly
//   future  -> /flights/{ident} is hard-capped ~2 days out; beyond that needs /schedules
//
// Both caps are AeroAPI's, not ours, but they fail differently, which matters. The future cap is
// silent — the endpoint just returns nothing. The past cap is not: a `start` more than ~10 days
// back is rejected with a 400 for the whole request ("Invalid start bound: time is too far in the
// past"), which used to surface to the traveller as a failed search for any flight older than that
// — reported live for CX488 two months back. So the window arithmetic decides both whether a real
// flight is findable and whether the search errors at all, which is what these cover.

import { assert, assertEquals, assertFalse } from "jsr:@std/assert";
import { dateWindow, isPastDate } from "./index.ts";

const DAY_MS = 24 * 60 * 60 * 1000;

function isoDay(offsetDays: number, from: Date = new Date()): string {
  return new Date(from.getTime() + offsetDays * DAY_MS).toISOString().slice(0, 10);
}

// MARK: - Future

Deno.test("dateWindow: a date beyond AeroAPI's 2-day live cap reports itself as clamped", () => {
  const { endISO, wasClamped } = dateWindow(isoDay(30));
  assert(wasClamped, "a month out must flag as clamped so /schedules is consulted");
  assert(new Date(endISO).getTime() <= Date.now() + 2 * DAY_MS, "end must not exceed the live cap");
});

Deno.test("dateWindow: a clamped window still has usable width", () => {
  // The failure this guards is an inverted or zero-width range, which AeroAPI rejects outright
  // ("type is incorrect") rather than treating as an empty result.
  for (const offset of [3, 10, 100, 364]) {
    const { startISO, endISO } = dateWindow(isoDay(offset));
    const width = new Date(endISO).getTime() - new Date(startISO).getTime();
    assert(width >= 60 * 60 * 1000, `offset ${offset} produced a ${width}ms window`);
  }
});

Deno.test("dateWindow: tomorrow clamps, but the clamped window still spans the whole requested day", () => {
  // Counter-intuitive but correct: the window reaches two days *past the requested date* while
  // AeroAPI caps at two days from *now*, so even tomorrow trips the clamp. That's harmless for
  // correctness — what matters is that the clamped end still falls beyond the end of the requested
  // day, so the live endpoint can find the flight — but it does mean a next-day search also pays
  // for a /schedules call it doesn't need.
  const target = isoDay(1);
  const { endISO, wasClamped } = dateWindow(target);
  assert(wasClamped);
  const endOfRequestedDay = new Date(`${target}T23:59:59Z`).getTime();
  assert(
    new Date(endISO).getTime() > endOfRequestedDay,
    "clamped window must still cover the whole requested day, or a late departure is unfindable",
  );
});

// MARK: - Present

Deno.test("dateWindow: today is never clamped", () => {
  const { wasClamped } = dateWindow(isoDay(0));
  assertFalse(wasClamped, "clamping today would send same-day searches down the /schedules path");
});

Deno.test("dateWindow: the window brackets the requested day on both sides", () => {
  // A local day spills either side of its UTC day, so an overnight departure has to stay inside.
  const target = isoDay(0);
  const { startISO, endISO } = dateWindow(target);
  const dayStart = new Date(`${target}T00:00:00Z`).getTime();
  assert(new Date(startISO).getTime() <= dayStart, "start must precede the requested day");
  assert(new Date(endISO).getTime() > dayStart, "end must fall after the requested day begins");
});

// MARK: - Past

Deno.test("isPastDate: yesterday is past, today is not, tomorrow is not", () => {
  assert(isPastDate(isoDay(-1)));
  assertFalse(isPastDate(isoDay(0)));
  assertFalse(isPastDate(isoDay(1)));
});

Deno.test("isPastDate: compares whole UTC days, not instants", () => {
  // Late in the UTC day, "today" must still not count as past — otherwise every afternoon search
  // for a flight later the same day would spend a pointless /history call.
  const lateToday = new Date("2026-03-14T23:59:00Z");
  assertFalse(isPastDate("2026-03-14", lateToday));
  assert(isPastDate("2026-03-13", lateToday));
});

Deno.test("dateWindow: a past date is never clamped, so it never diverts to /schedules", () => {
  // /schedules is the *future* fallback. A past date reaching it would be querying the wrong side
  // of now; history is what serves these.
  for (const offset of [-1, -9, -45, -400]) {
    const { wasClamped } = dateWindow(isoDay(offset));
    assertFalse(wasClamped, `offset ${offset} should not clamp`);
  }
});

Deno.test("dateWindow: an old date still produces a forward-ordered window for /history", () => {
  const { startISO, endISO } = dateWindow(isoDay(-45));
  assert(new Date(startISO) < new Date(endISO), "history windows must not be inverted");
  // fetchHistoricalFlights chunks at 6 days; a single-day search must stay inside one chunk so it
  // costs exactly one AeroAPI call.
  const width = new Date(endISO).getTime() - new Date(startISO).getTime();
  assert(width <= 6 * DAY_MS, `window spans ${width / DAY_MS} days, which would chunk into extra calls`);
});

// MARK: - Formatting

Deno.test("dateWindow: timestamps carry no fractional seconds", () => {
  // AeroAPI's parser has rejected trailing milliseconds ("type is incorrect").
  for (const offset of [-45, -1, 0, 1, 30]) {
    const { startISO, endISO } = dateWindow(isoDay(offset));
    assertEquals(startISO.includes("."), false, `start ${startISO}`);
    assertEquals(endISO.includes("."), false, `end ${endISO}`);
  }
});

// MARK: - Past

// The reported case: a search for a flight two months ago returned AeroAPI's own "time is too far
// in the past" 400 rather than the flight. /history answers that day perfectly well; the live call
// just has to be skipped rather than attempted and allowed to throw.
Deno.test("dateWindow: a date beyond the live endpoint's ~10-day memory says so", () => {
  const { tooOldForLive } = dateWindow(isoDay(-62));
  assert(tooOldForLive, "two months back must skip /flights/{ident} and go to /history");
});

Deno.test("dateWindow: recent past days are still answered by the live endpoint", () => {
  for (const offset of [0, -1, -3, -5, -7]) {
    const { tooOldForLive } = dateWindow(isoDay(offset));
    assertFalse(tooOldForLive, `${offset} days back is within the live window and shouldn't be skipped`);
  }
});

// The margin is deliberate: AeroAPI enforces its limit against its own clock when the request
// lands, so a window built exactly on the boundary can cross it in flight. Day 9 is the last one
// the live endpoint is asked about, not day 10.
Deno.test("dateWindow: the cutoff keeps a margin inside AeroAPI's stated 10 days", () => {
  assertFalse(dateWindow(isoDay(-7)).tooOldForLive, "7 days back is comfortably inside");
  assert(dateWindow(isoDay(-11)).tooOldForLive, "11 days back is outside");
});

// A future date must never be mistaken for one that's too old — the window's `start` is pulled a
// day back from the target, and the clamp for the future cap moves `start` too.
Deno.test("dateWindow: future dates are never treated as too old", () => {
  for (const offset of [1, 2, 5, 30, 300]) {
    assertFalse(dateWindow(isoDay(offset)).tooOldForLive, `${offset} days out must not skip the live endpoint as 'too old'`);
  }
});
