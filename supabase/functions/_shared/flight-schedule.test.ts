// Tests for the flight-refresh cadence and the one-shot reminder windows.
//
// This logic decides both how much AeroAPI billing we incur and how fast a departure is noticed,
// and it has already been the source of two real bugs in mirror image: a flight that overran its
// ETA and one that departed late both dropped out of the 1-minute tier at the exact moment they
// mattered, because both near-event checks require the countdown to still be positive. Those two
// cases are pinned below so they can't silently regress.
//
// Run with: deno test supabase/functions/_shared/flight-schedule.test.ts

import { assertEquals } from "jsr:@std/assert";
import { type FlightRow } from "./flight-sync.ts";
import {
  ARRIVAL_REMINDER_1H_WINDOW_MS,
  ARRIVAL_REMINDER_30M_WINDOW_MS,
  bestKnownArrival,
  isDue,
  isDueForArrivalReminder,
  isDueForPreDepartureReminder,
  shouldResetArrivalReminder,
} from "./flight-schedule.ts";

const NOW = Date.parse("2026-08-17T12:00:00Z");
const MINUTE = 60 * 1000;
const HOUR = 60 * MINUTE;

function at(offsetMs: number): string {
  return new Date(NOW + offsetMs).toISOString();
}

/// Only the fields these predicates actually read; the rest of FlightRow is irrelevant here.
function flight(overrides: Partial<FlightRow> = {}): FlightRow {
  return {
    status: "scheduled",
    scheduled_out: at(48 * HOUR),
    scheduled_in: null,
    estimated_out: null,
    estimated_in: null,
    actual_out: null,
    last_refreshed_at: at(-1 * MINUTE),
    pre_departure_notified: false,
    ...overrides,
  } as unknown as FlightRow;
}

Deno.test("isDue: a flight with no schedule is always worth a look", () => {
  assertEquals(isDue(flight({ scheduled_out: null, last_refreshed_at: at(-1000) }), NOW), true);
});

Deno.test("isDue: never refreshed yet is always due", () => {
  assertEquals(isDue(flight({ last_refreshed_at: null }), NOW), true);
});

Deno.test("isDue: 1-minute tier inside the 10 minutes before departure", () => {
  const near: Partial<FlightRow> = { scheduled_out: at(5 * MINUTE) };
  assertEquals(isDue(flight({ ...near, last_refreshed_at: at(-90 * 1000) }), NOW), true);
  assertEquals(isDue(flight({ ...near, last_refreshed_at: at(-30 * 1000) }), NOW), false);
});

Deno.test("isDue: 1-minute tier inside the 10 minutes before arrival", () => {
  const near: Partial<FlightRow> = { status: "in_air", scheduled_out: at(-3 * HOUR), scheduled_in: at(5 * MINUTE), actual_out: at(-3 * HOUR) };
  assertEquals(isDue(flight({ ...near, last_refreshed_at: at(-90 * 1000) }), NOW), true);
  assertEquals(isDue(flight({ ...near, last_refreshed_at: at(-30 * 1000) }), NOW), false);
});

// The bug that prompted the isOverdueForDeparture branch: a flight whose ETA has passed with no
// actual_out is seconds from a takeoff confirmation, but every near-event check requires a
// positive countdown, so it used to fall through to the 12-minute mid-cruise tier. Reported live
// as a departure noticed ~10 minutes after the fact.
Deno.test("isDue: departure overdue with no actual_out stays on the 1-minute tier", () => {
  const overdue: Partial<FlightRow> = { status: "boarding", scheduled_out: at(-4 * MINUTE), actual_out: null };
  assertEquals(isDue(flight({ ...overdue, last_refreshed_at: at(-90 * 1000) }), NOW), true);
  assertEquals(isDue(flight({ ...overdue, last_refreshed_at: at(-30 * 1000) }), NOW), false);
});

Deno.test("isDue: once actual_out is known a mid-cruise flight drops to the 12-minute tier", () => {
  const cruising: Partial<FlightRow> = {
    status: "in_air",
    scheduled_out: at(-2 * HOUR),
    actual_out: at(-2 * HOUR),
    scheduled_in: at(6 * HOUR),
  };
  assertEquals(isDue(flight({ ...cruising, last_refreshed_at: at(-5 * MINUTE) }), NOW), false);
  assertEquals(isDue(flight({ ...cruising, last_refreshed_at: at(-13 * MINUTE) }), NOW), true);
});

// The arrival-side twin: past its ETA with no landed/arrived confirmation is exactly when the
// "landed" transition (and the Live Activity end push) is imminent.
Deno.test("isDue: arrival overdue without confirmation stays on the 1-minute tier", () => {
  const overdue: Partial<FlightRow> = {
    status: "in_air",
    scheduled_out: at(-8 * HOUR),
    actual_out: at(-8 * HOUR),
    scheduled_in: at(-6 * MINUTE),
  };
  assertEquals(isDue(flight({ ...overdue, last_refreshed_at: at(-90 * 1000) }), NOW), true);
  assertEquals(isDue(flight({ ...overdue, last_refreshed_at: at(-30 * 1000) }), NOW), false);
});

Deno.test("isDue: estimated times take precedence over scheduled ones", () => {
  // Scheduled departure is 5 hours out (15-minute tier), but AeroAPI now estimates 5 minutes,
  // which should pull it onto the 1-minute tier.
  const f = flight({ scheduled_out: at(5 * HOUR), estimated_out: at(5 * MINUTE), last_refreshed_at: at(-90 * 1000) });
  assertEquals(isDue(f, NOW), true);
});

Deno.test("isDue: 2-minute tier within 2 hours of departure", () => {
  const soon: Partial<FlightRow> = { scheduled_out: at(90 * MINUTE) };
  assertEquals(isDue(flight({ ...soon, last_refreshed_at: at(-3 * MINUTE) }), NOW), true);
  assertEquals(isDue(flight({ ...soon, last_refreshed_at: at(-1 * MINUTE) }), NOW), false);
});

Deno.test("isDue: 15-minute tier between 2 and 24 hours out", () => {
  const later: Partial<FlightRow> = { scheduled_out: at(10 * HOUR) };
  assertEquals(isDue(flight({ ...later, last_refreshed_at: at(-20 * MINUTE) }), NOW), true);
  assertEquals(isDue(flight({ ...later, last_refreshed_at: at(-10 * MINUTE) }), NOW), false);
});

Deno.test("isDue: 6-hour tier beyond 24 hours out", () => {
  const distant: Partial<FlightRow> = { scheduled_out: at(48 * HOUR) };
  assertEquals(isDue(flight({ ...distant, last_refreshed_at: at(-7 * HOUR) }), NOW), true);
  assertEquals(isDue(flight({ ...distant, last_refreshed_at: at(-5 * HOUR) }), NOW), false);
});

Deno.test("isDueForPreDepartureReminder: fires once inside the window, never after actual_out", () => {
  assertEquals(isDueForPreDepartureReminder(flight({ scheduled_out: at(5 * MINUTE) }), NOW), true);
  assertEquals(isDueForPreDepartureReminder(flight({ scheduled_out: at(30 * MINUTE) }), NOW), false);
  // Already sent.
  assertEquals(
    isDueForPreDepartureReminder(flight({ scheduled_out: at(5 * MINUTE), pre_departure_notified: true }), NOW),
    false,
  );
  // Already left — "wish them a safe flight" is meaningless now.
  assertEquals(
    isDueForPreDepartureReminder(flight({ scheduled_out: at(5 * MINUTE), actual_out: at(-1 * MINUTE) }), NOW),
    false,
  );
});

Deno.test("isDueForArrivalReminder: respects its window, the notified flag and terminal statuses", () => {
  const inFlight: Partial<FlightRow> = { status: "in_air", scheduled_in: at(45 * MINUTE) };
  // 45 minutes out: inside the 1h window, outside the 30m one.
  assertEquals(isDueForArrivalReminder(flight(inFlight), NOW, ARRIVAL_REMINDER_1H_WINDOW_MS, false), true);
  assertEquals(isDueForArrivalReminder(flight(inFlight), NOW, ARRIVAL_REMINDER_30M_WINDOW_MS, false), false);
  // Already notified for this window.
  assertEquals(isDueForArrivalReminder(flight(inFlight), NOW, ARRIVAL_REMINDER_1H_WINDOW_MS, true), false);
  // Landed — no "landing in an hour" after the fact.
  assertEquals(
    isDueForArrivalReminder(flight({ ...inFlight, status: "landed" }), NOW, ARRIVAL_REMINDER_1H_WINDOW_MS, false),
    false,
  );
  // Arrival already passed.
  assertEquals(
    isDueForArrivalReminder(flight({ ...inFlight, scheduled_in: at(-1 * MINUTE) }), NOW, ARRIVAL_REMINDER_1H_WINDOW_MS, false),
    false,
  );
});

Deno.test("shouldResetArrivalReminder: only past the 10-minute noise floor", () => {
  const base = at(3 * HOUR);
  assertEquals(shouldResetArrivalReminder(base, at(3 * HOUR + 5 * MINUTE)), false);
  assertEquals(shouldResetArrivalReminder(base, at(3 * HOUR + 15 * MINUTE)), true);
  // Moving earlier counts just as much as moving later.
  assertEquals(shouldResetArrivalReminder(base, at(3 * HOUR - 15 * MINUTE)), true);
  // Nothing to compare against.
  assertEquals(shouldResetArrivalReminder(null, base), false);
  assertEquals(shouldResetArrivalReminder(base, null), false);
  assertEquals(shouldResetArrivalReminder("not a date", base), false);
});

Deno.test("bestKnownArrival: prefers the estimate", () => {
  assertEquals(bestKnownArrival(flight({ scheduled_in: at(HOUR), estimated_in: at(2 * HOUR) })), at(2 * HOUR));
  assertEquals(bestKnownArrival(flight({ scheduled_in: at(HOUR) })), at(HOUR));
  assertEquals(bestKnownArrival(flight({ scheduled_in: null })), null);
});
