// The stale date every Live Activity push carries (FLT-2).
//
// An APNs Live Activity update that has no `stale-date` replaces the card's content with content
// that has no stale date at all. The app sets one when it starts or updates a card (the arrival,
// or a day past departure: see `LiveActivityManager.staleDate`), because that is the only thing
// that re-renders the card at landing and stops "Arrives in" counting back up. Every push from here
// used to drop it, so after the first one a landed flight could sit at "Arrives in 12 min",
// counting up, with no sign it was out of date. These pin the same rule as the app.
//
// Run with: deno test supabase/functions/_shared/live-activity-stale-date.test.ts

import { assertEquals } from "jsr:@std/assert";
import { type FlightRow, liveActivityStaleDateUnix } from "./flight-sync.ts";

const NOW = Date.parse("2026-11-02T08:00:00Z");
const unix = (iso: string) => Math.round(Date.parse(iso) / 1000);

function row(fields: Partial<FlightRow>): FlightRow {
  return {
    scheduled_out: null,
    scheduled_in: null,
    estimated_out: null,
    estimated_in: null,
    ...fields,
  } as FlightRow;
}

Deno.test("the stale date is the estimated arrival when there is one", () => {
  const flight = row({ scheduled_in: "2026-11-02T10:00:00Z", estimated_in: "2026-11-02T10:40:00Z" });
  assertEquals(liveActivityStaleDateUnix(flight, NOW), unix("2026-11-02T10:40:00Z"));
});

Deno.test("then the scheduled arrival", () => {
  assertEquals(liveActivityStaleDateUnix(row({ scheduled_in: "2026-11-02T10:00:00Z" }), NOW), unix("2026-11-02T10:00:00Z"));
});

// Across midnight UTC, which is where a day added by hand to a local date string would go wrong.
Deno.test("with no arrival at all, a day past the departure", () => {
  const flight = row({ scheduled_out: "2026-11-02T23:30:00Z", estimated_out: "2026-11-02T23:55:00Z" });
  assertEquals(liveActivityStaleDateUnix(flight, NOW), unix("2026-11-03T23:55:00Z"));
});

Deno.test("with no times at all, twelve hours from now", () => {
  assertEquals(liveActivityStaleDateUnix(row({}), NOW), Math.round(NOW / 1000) + 12 * 3600);
});
