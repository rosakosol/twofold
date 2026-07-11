// Pure status-derivation logic, deliberately split out of flight-sync.ts with zero runtime
// imports (only a type-only import from aeroapi.ts, which is erased at compile time). This lets
// resolve-flight/index.ts derive the same status string as flight-sync.ts without pulling in
// flight-sync's transitive dependency chain (notify.ts -> apns.ts -> npm:jose), which resolve-
// flight doesn't otherwise need since it never touches the DB.

import type { AeroFlight } from "./aeroapi.ts";

export type FlightStatus =
  | "scheduled"
  | "boarding"
  | "departed"
  | "in_air"
  | "landing_soon"
  | "landed"
  | "arrived"
  | "delayed"
  | "cancelled"
  | "diverted";

const BOARDING_WINDOW_MS = 40 * 60 * 1000;
const LANDING_SOON_WINDOW_MS = 30 * 60 * 1000;
const DELAY_THRESHOLD_SECONDS = 300;

// Only the subset of AeroFlight fields the derivation actually reads — lets callers pass either
// a full AeroFlight or a partial/mapped row shape with the same field names.
export type FlightStatusInput = Pick<
  AeroFlight,
  | "cancelled"
  | "diverted"
  | "actual_out"
  | "actual_off"
  | "actual_on"
  | "actual_in"
  | "scheduled_out"
  | "estimated_out"
  | "estimated_in"
  | "scheduled_in"
  | "progress_percent"
  | "departure_delay"
  | "arrival_delay"
>;

export function deriveFlightStatus(f: FlightStatusInput, now: Date = new Date()): FlightStatus {
  if (f.cancelled) return "cancelled";
  if (f.diverted) return "diverted";
  if (f.actual_in) return "arrived";
  if (f.actual_on) return "landed";

  if (f.actual_off && !f.actual_on) {
    const arrivalEta = f.estimated_in ?? f.scheduled_in;
    const minutesToArrival = arrivalEta ? (new Date(arrivalEta).getTime() - now.getTime()) : Infinity;
    const nearArrival = minutesToArrival <= LANDING_SOON_WINDOW_MS && minutesToArrival >= -LANDING_SOON_WINDOW_MS;
    if ((f.progress_percent ?? 0) > 85 || nearArrival) return "landing_soon";
    return "in_air";
  }

  if (f.actual_out && !f.actual_off) return "departed";

  const departureEta = f.estimated_out ?? f.scheduled_out;
  if (!f.actual_out && departureEta) {
    const msToDeparture = new Date(departureEta).getTime() - now.getTime();
    if (msToDeparture <= BOARDING_WINDOW_MS && msToDeparture >= -BOARDING_WINDOW_MS) return "boarding";
  }

  const departureDelay = f.departure_delay ?? 0;
  const arrivalDelay = f.arrival_delay ?? 0;
  if (departureDelay > DELAY_THRESHOLD_SECONDS || arrivalDelay > DELAY_THRESHOLD_SECONDS) return "delayed";

  return "scheduled";
}
