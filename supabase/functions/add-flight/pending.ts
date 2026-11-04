// The shape a pending (schedule-only) candidate must have before add-flight will look at it.
//
// Split out of index.ts for the reason allowance.ts is: that module calls `Deno.serve` at import.
//
// A pending candidate is the one input add-flight takes flight fields from, and before this only
// `flightNumberIata` and `scheduledOut` had to be present — any value of either. What that cost:
// a departure in the past with no arrival never arrives and never archives, and sits on the
// refresher's one-minute "overdue for departure" tier, making a billed /schedules call per tick for
// a flight that was never real. These checks are the cheap first line; add-flight then confirms
// the flight against /schedules itself (see `confirmPendingSchedule`) and stores AeroAPI's times.

// A schedule-only candidate is at least two days out (closer than that, AeroAPI's live endpoint has
// it with an fa_flight_id), so this slack only covers clocks and a confirmation screen left open.
export const PENDING_DEPARTURE_SKEW_MS = 60 * 60 * 1000;
// /schedules refuses a window ending more than a year out, and the confirmation asks for a day
// either side, so the departure has to leave room for that day.
export const PENDING_MAX_LEAD_MS = 360 * 24 * 60 * 60 * 1000;
// The longest scheduled flight is under 19 hours gate to gate.
export const PENDING_MAX_DURATION_MS = 20 * 60 * 60 * 1000;

export interface PendingShape {
  flightNumberIata?: unknown;
  scheduledOut?: unknown;
  scheduledIn?: unknown;
}

// Same shape the refresher's designator split accepts (flight-sync.ts's
// splitPendingFlightDesignator) — a pending row it can't split could never resolve.
const DESIGNATOR = /^[A-Z]{2,3}\d{1,4}$/;

function instant(value: unknown): number | null {
  if (typeof value !== "string") return null;
  const ms = Date.parse(value);
  return Number.isNaN(ms) ? null : ms;
}

/// Null when the candidate is acceptable, otherwise the reason it is not, for a 400.
export function pendingProblem(pending: PendingShape, now: number = Date.now()): string | null {
  if (typeof pending.flightNumberIata !== "string" || !DESIGNATOR.test(pending.flightNumberIata.trim().toUpperCase())) {
    return "'pending.flightNumberIata' must be a flight number like QF35";
  }
  const out = instant(pending.scheduledOut);
  if (out === null) return "'pending.scheduledOut' must be an ISO 8601 time";
  if (out < now - PENDING_DEPARTURE_SKEW_MS) return "'pending.scheduledOut' has already passed";
  if (out > now + PENDING_MAX_LEAD_MS) return "'pending.scheduledOut' is too far in the future";
  if (pending.scheduledIn !== undefined && pending.scheduledIn !== null) {
    const arrival = instant(pending.scheduledIn);
    if (arrival === null) return "'pending.scheduledIn' must be an ISO 8601 time";
    if (arrival <= out || arrival - out > PENDING_MAX_DURATION_MS) {
      return "'pending.scheduledIn' must be after 'scheduledOut', within a flight's length of it";
    }
  }
  return null;
}
