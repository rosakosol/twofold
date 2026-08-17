// The pure scheduling predicates behind the flight-refresh cron: when a flight is due for another
// AeroAPI poll, and when each one-shot reminder should fire.
//
// Extracted from refresh-due-flights/index.ts so they can be tested. That file has a top-level
// `Deno.serve(...)`, so importing anything from it starts a server — which meant this logic, the
// part that decides how much AeroAPI billing we incur and how quickly a departure is noticed, was
// the least testable code in the project despite being entirely pure. See flight-schedule.test.ts.
//
// Behaviour is unchanged by the move; the tests were written against the tiering as documented in
// refresh-due-flights/index.ts's header comment.

import { type FlightRow } from "./flight-sync.ts";

export const ACTIVE_STATUSES = ["boarding", "departed", "in_air", "landing_soon"];

export const NEAR_EVENT_WINDOW_MS = 10 * 60 * 1000;

export function isDue(flight: FlightRow, now: number): boolean {
  if (!flight.scheduled_out) return true; // no schedule to gauge against — always worth a look
  const lastRefreshedMs = flight.last_refreshed_at ? new Date(flight.last_refreshed_at).getTime() : null;
  const staleMs = lastRefreshedMs === null ? Infinity : now - lastRefreshedMs;

  // Best-known (not just scheduled) times — once AeroAPI reports an estimate, that's a more
  // honest read of "how close is this to actually happening" than the original schedule.
  const bestDeparture = flight.estimated_out ?? flight.scheduled_out;
  const bestArrival = flight.estimated_in ?? flight.scheduled_in;
  const msToDeparture = new Date(bestDeparture).getTime() - now;
  const msToArrival = bestArrival ? new Date(bestArrival).getTime() - now : null;
  const isNearDeparture = msToDeparture >= 0 && msToDeparture <= NEAR_EVENT_WINDOW_MS;
  const isNearArrival = msToArrival !== null && msToArrival >= 0 && msToArrival <= NEAR_EVENT_WINDOW_MS;
  // Best-known arrival has already passed but AeroAPI hasn't confirmed landed/arrived yet — this
  // is exactly the moment a "landed" transition (and the Live Activity "end" push it triggers) is
  // imminent, so it needs the same tight cadence as the near-arrival window above, not whatever
  // slower tier a non-terminal status would otherwise fall into. Without this, a flight that
  // overran its ETA dropped out of isNearArrival (which requires msToArrival >= 0) right when it
  // mattered most, and — after the isActive tier below was widened to 12 minutes — could sit
  // showing stale "arriving soon" content for a while past actual touchdown before the next poll
  // even looked for a status change. `reconcileOverdueArrival`'s own 20-minute force-correct is
  // the hard backstop if AeroAPI itself never confirms; this is what makes catching a *timely*
  // real confirmation likely well before that backstop ever has to fire.
  const isOverdueForArrival = msToArrival !== null && msToArrival < 0;
  // The departure-side twin of isOverdueForArrival above, and the same bug in mirror image: best-
  // known departure has passed but AeroAPI hasn't reported an actual_out yet, so takeoff
  // confirmation is imminent. isNearDeparture can't cover this — it requires msToDeparture >= 0,
  // so a flight drops out of the 1-minute tier the instant its ETA passes, which is the moment it
  // matters most. Worse, a flight still sitting in `boarding` (an ACTIVE_STATUS) then fell through
  // to the isActive tier below, whose cadence was widened from 2 to 12 minutes in 3f7cc27 for
  // mid-cruise flights — so a delayed departure could go a full 12 minutes before anyone was told
  // it had left. Reported live: a departure noticed ~10 minutes after the fact.
  const isOverdueForDeparture = msToDeparture < 0 && !flight.actual_out;
  if (isNearDeparture || isNearArrival || isOverdueForArrival || isOverdueForDeparture) {
    return staleMs > 1 * 60 * 1000;
  }

  // Reaching here means none of the near/overdue branches above applied — so an active flight at
  // this point is genuinely mid-cruise (or boarding well before its own 10-minute near-departure
  // window), with a confirmed actual_out behind it and its arrival still comfortably ahead. Not
  // the moments right around takeoff/landing: those are all claimed by the 1-minute tier above,
  // which is what keeps this slower cadence safe. AeroAPI's own answer barely moves between polls
  // in this state (ETA/progress percent drift slowly), so it can afford to be far less aggressive.
  const isActive = ACTIVE_STATUSES.includes(flight.status);
  if (isActive) {
    return staleMs > 12 * 60 * 1000;
  }
  if (msToDeparture <= 2 * 60 * 60 * 1000) {
    return staleMs > 2 * 60 * 1000;
  }
  if (msToDeparture <= 24 * 60 * 60 * 1000) {
    return staleMs > 15 * 60 * 1000;
  }
  return lastRefreshedMs === null || staleMs > 6 * 60 * 60 * 1000;
}

// "Wish them a safe flight" nudge to the *other* partner — fires once per flight, guarded by
// pre_departure_notified (see 20260717030000_flight_pre_departure_notified.sql), while it's
// within 10 minutes of its best-known departure time and hasn't actually left yet. Near-departure
// flights are refreshed on essentially every cron tick already (isDue's 2-minute staleness
// threshold is well under this function's 5-minute schedule), so checking only right after a
// due-refresh is a safe simplification rather than re-evaluating every skipped flight too.
export const PRE_DEPARTURE_WINDOW_MS = 10 * 60 * 1000;

export function isDueForPreDepartureReminder(flight: FlightRow, now: number): boolean {
  if (flight.pre_departure_notified || flight.actual_out) return false;
  const bestDeparture = flight.estimated_out ?? flight.scheduled_out;
  if (!bestDeparture) return false;
  return new Date(bestDeparture).getTime() - now <= PRE_DEPARTURE_WINDOW_MS;
}

// Fixed-offset arrival reminders — "Landing in 1 hour" / "Landing in 30 minutes" — replacing the
// old "arrival_time_change" push that re-fired every time AeroAPI's ETA drifted by 10+ minutes
// (see flight-sync.ts diffEvents, which no longer emits that event). One-shot per window, guarded
// by arrival_1h_notified/arrival_30m_notified (see the accompanying migration), with the same
// "near-arrival flights already refresh every ~1-2 min" simplification isDueForPreDepartureReminder
// above relies on — only checked right after a due-refresh, not re-evaluated for skipped flights.
export const ARRIVAL_REMINDER_1H_WINDOW_MS = 60 * 60 * 1000;
export const ARRIVAL_REMINDER_30M_WINDOW_MS = 30 * 60 * 1000;

// Same 10-minute noise floor flight-sync.ts uses for its own arrival-estimate diffing — only
// reschedule (reset the notified flag so the reminder can fire again at the new time) once the
// predicted arrival has actually moved meaningfully, not on routine AeroAPI re-estimation drift.
export const ARRIVAL_REMINDER_RESCHEDULE_THRESHOLD_MS = 10 * 60 * 1000;

export const ARRIVAL_TERMINAL_STATUSES = ["landed", "arrived", "cancelled", "diverted"];

export function bestKnownArrival(flight: FlightRow): string | null {
  return flight.estimated_in ?? flight.scheduled_in;
}

export function shouldResetArrivalReminder(notifiedFor: string | null, currentArrival: string | null): boolean {
  if (!notifiedFor || !currentArrival) return false;
  const prevMs = Date.parse(notifiedFor);
  const currMs = Date.parse(currentArrival);
  if (Number.isNaN(prevMs) || Number.isNaN(currMs)) return false;
  return Math.abs(currMs - prevMs) >= ARRIVAL_REMINDER_RESCHEDULE_THRESHOLD_MS;
}

export function isDueForArrivalReminder(flight: FlightRow, now: number, windowMs: number, notified: boolean): boolean {
  if (notified || ARRIVAL_TERMINAL_STATUSES.includes(flight.status)) return false;
  const arrival = bestKnownArrival(flight);
  if (!arrival) return false;
  const msToArrival = new Date(arrival).getTime() - now;
  return msToArrival >= 0 && msToArrival <= windowMs;
}

// Longest plausible gap between a flight's best-known arrival and AeroAPI actually recording an
// `actual_in`. Generous — arrival reporting is the flakiest field in the feed — but finite.
export const ARRIVAL_REPORTING_GRACE_MS = 6 * 60 * 60 * 1000;
// Fallback bound for a flight with no arrival estimate at all: longer than any scheduled commercial
// flight, so a genuinely airborne ultra-long-haul is never excluded.
export const MAX_PLAUSIBLE_FLIGHT_MS = 24 * 60 * 60 * 1000;

// "Departed and not yet arrived" — but bounded in time, which it previously wasn't.
//
// The old test was just `actual_out && !actual_in`, which is true *forever* for any flight AeroAPI
// never got an arrival for. Since callers use this to bypass the same-day filter (a genuinely
// airborne flight shouldn't be excluded on a date technicality), one stale row poisoned every later
// search for that number: searching CX6104 for 17 Aug returned the 16 Aug departure alongside it,
// because the 16th had `actual_out` and no `actual_in` and so still counted as "in progress". Two
// rows, same number, same route, same local departure time, no date shown on either — with no way
// to tell which was which. Confirmed against live AeroAPI data.
//
// A flight is only still in the air if its arrival hasn't already come and gone.
export function isFlightInProgress(
  f: { actual_out?: string | null; actual_in?: string | null; scheduled_in?: string | null; estimated_in?: string | null },
  nowMs: number = Date.now(),
): boolean {
  if (!f.actual_out || f.actual_in) return false;

  const arrival = f.estimated_in ?? f.scheduled_in;
  if (arrival) {
    const arrivalMs = Date.parse(arrival);
    if (!Number.isNaN(arrivalMs)) return arrivalMs >= nowMs - ARRIVAL_REPORTING_GRACE_MS;
  }

  // No usable arrival estimate (the CI5175 case: airborne with almost every timestamp null) — fall
  // back to how long ago it left, which is the only signal there is.
  const outMs = Date.parse(f.actual_out);
  if (Number.isNaN(outMs)) return true;
  return outMs >= nowMs - MAX_PLAUSIBLE_FLIGHT_MS;
}
