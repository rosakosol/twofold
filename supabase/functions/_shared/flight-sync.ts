// The single shared diff/persist routine for flight data. Both the polling paths
// (refresh-flight, refresh-due-flights) and the webhook path (aeroapi-webhook) call syncFlight()
// so a given change is only ever detected, persisted, and notified-about once, in one place.

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import {
  type AeroFlight,
  fetchAirportCoordinates,
  fetchAirportWeather,
  fetchFlightByFaId,
  fetchPosition,
} from "./aeroapi.ts";
import { fetchLivePosition } from "./adsb.ts";
import { fetchRouteFallback } from "./adsbdb.ts";
import { lookupAirlineName } from "./airlines.ts";
import { deriveFlightStatus, type FlightStatus } from "./flight-status.ts";
import { notifyForEvent } from "./notify.ts";
import { sendLiveActivityUpdate, toCocoaTimestamp } from "./apns.ts";

// Mirrors supabase/migrations/20260712000000_flight_tracking.sql's `flights` table exactly.
export interface FlightRow {
  id: string;
  trip_id: string | null;
  couple_id: string;
  created_by: string | null;
  fa_flight_id: string | null;
  flight_number_iata: string | null;
  flight_number_icao: string | null;
  atc_ident: string | null;
  airline_name: string | null;
  airline_code: string | null;
  airline_logo_url: string | null;
  origin_iata: string | null;
  origin_icao: string | null;
  origin_name: string | null;
  origin_city: string | null;
  origin_timezone: string | null;
  origin_latitude: number | null;
  origin_longitude: number | null;
  destination_iata: string | null;
  destination_icao: string | null;
  destination_name: string | null;
  destination_city: string | null;
  destination_timezone: string | null;
  destination_latitude: number | null;
  destination_longitude: number | null;
  aircraft_type: string | null;
  registration: string | null;
  route: string | null;
  scheduled_out: string | null;
  scheduled_off: string | null;
  scheduled_on: string | null;
  scheduled_in: string | null;
  estimated_out: string | null;
  estimated_off: string | null;
  estimated_on: string | null;
  estimated_in: string | null;
  actual_out: string | null;
  actual_off: string | null;
  actual_on: string | null;
  actual_in: string | null;
  departure_delay_seconds: number | null;
  arrival_delay_seconds: number | null;
  terminal_origin: string | null;
  gate_origin: string | null;
  terminal_destination: string | null;
  gate_destination: string | null;
  baggage_claim: string | null;
  cancelled: boolean;
  diverted: boolean;
  status: FlightStatus;
  position_latitude: number | null;
  position_longitude: number | null;
  position_altitude: number | null;
  position_groundspeed: number | null;
  position_heading: number | null;
  position_updated_at: string | null;
  weather_origin: Record<string, unknown> | null;
  weather_destination: Record<string, unknown> | null;
  weather_updated_at: string | null;
  last_refreshed_at: string | null;
  tracking_enabled: boolean;
  pre_departure_notified: boolean;
}

// Fields sourced directly from an AeroFlight, shared by add-flight's initial insert and
// flight-sync's per-refresh update. Deliberately excludes columns owned by other flows
// (id/couple_id/trip_id/created_by, position_*, weather_*, tracking_enabled).
export type MappedAeroFields = Pick<
  FlightRow,
  | "fa_flight_id"
  | "flight_number_iata"
  | "flight_number_icao"
  | "atc_ident"
  | "airline_name"
  | "airline_code"
  | "airline_logo_url"
  | "origin_iata"
  | "origin_icao"
  | "origin_name"
  | "origin_city"
  | "origin_timezone"
  | "origin_latitude"
  | "origin_longitude"
  | "destination_iata"
  | "destination_icao"
  | "destination_name"
  | "destination_city"
  | "destination_timezone"
  | "destination_latitude"
  | "destination_longitude"
  | "aircraft_type"
  | "registration"
  | "route"
  | "scheduled_out"
  | "scheduled_off"
  | "scheduled_on"
  | "scheduled_in"
  | "estimated_out"
  | "estimated_off"
  | "estimated_on"
  | "estimated_in"
  | "actual_out"
  | "actual_off"
  | "actual_on"
  | "actual_in"
  | "departure_delay_seconds"
  | "arrival_delay_seconds"
  | "terminal_origin"
  | "gate_origin"
  | "terminal_destination"
  | "gate_destination"
  | "baggage_claim"
  | "cancelled"
  | "diverted"
  | "status"
>;

// AeroAPI's `city` field on an airport is sometimes the airport's literal municipality rather
// than the metro area travelers actually know it by — Haneda (HND) comes back as "Ota" (the ward
// Haneda sits in) instead of "Tokyo", which read as a bug ("NH160 HND → JFK" showing "Ota → New
// York"). Our own `airports` table (seeded from a proper reference dataset, not AeroAPI) already
// has the traveler-recognizable city for HND and airports like it, so it's preferred here whenever
// a match exists; AeroAPI's own value is only a fallback for airports outside that table.
async function resolveAirportCity(
  client: SupabaseClient,
  iata: string | null | undefined,
  icao: string | null | undefined,
  fallback: string | null,
): Promise<string | null> {
  const code = iata || icao;
  if (!code) return fallback;
  try {
    const { data } = await client
      .from("airports")
      .select("city")
      .or(`iata.eq.${code},icao.eq.${code}`)
      .limit(1)
      .maybeSingle();
    return data?.city ?? fallback;
  } catch (err) {
    console.error("[flight-sync] airport city lookup threw:", (err as Error).message);
    return fallback;
  }
}

export async function mapAeroFlightToRow(client: SupabaseClient, aeroFlight: AeroFlight): Promise<MappedAeroFields> {
  const [originCity, destinationCity] = await Promise.all([
    resolveAirportCity(client, aeroFlight.origin?.code_iata, aeroFlight.origin?.code_icao, aeroFlight.origin?.city ?? null),
    resolveAirportCity(client, aeroFlight.destination?.code_iata, aeroFlight.destination?.code_icao, aeroFlight.destination?.city ?? null),
  ]);
  const mapped: MappedAeroFields = {
    fa_flight_id: aeroFlight.fa_flight_id ?? null,
    flight_number_iata: aeroFlight.ident_iata ?? aeroFlight.ident ?? null,
    flight_number_icao: aeroFlight.ident_icao ?? null,
    atc_ident: aeroFlight.atc_ident ?? null,
    // AeroAPI's /flights response only exposes an operator *code* (ICAO/IATA), never a display
    // name (confirmed absent from the documented field list, and AeroAPI has no name/logo
    // lookup endpoint at all per FlightAware's own support forum) — resolved against a curated
    // code -> name table for major airlines; stays null for anything not in that table rather
    // than guessing.
    airline_name: lookupAirlineName(aeroFlight.operator_iata, aeroFlight.operator_icao, aeroFlight.operator),
    airline_code: aeroFlight.operator_iata ?? aeroFlight.operator_icao ?? aeroFlight.operator ?? null,
    airline_logo_url: null,
    origin_iata: aeroFlight.origin?.code_iata ?? null,
    origin_icao: aeroFlight.origin?.code_icao ?? null,
    origin_name: aeroFlight.origin?.name ?? null,
    origin_city: originCity,
    origin_timezone: aeroFlight.origin?.timezone ?? null,
    // Not present on the /flights response fields confirmed from the docs (only the dedicated
    // /airports/{id} endpoint documents lat/long) — mapped opportunistically if the payload
    // happens to include it, otherwise left null. A supplementary airport lookup would be needed
    // to backfill these reliably; out of scope here, flagged for follow-up.
    origin_latitude: aeroFlight.origin?.latitude ?? null,
    origin_longitude: aeroFlight.origin?.longitude ?? null,
    destination_iata: aeroFlight.destination?.code_iata ?? null,
    destination_icao: aeroFlight.destination?.code_icao ?? null,
    destination_name: aeroFlight.destination?.name ?? null,
    destination_city: destinationCity,
    destination_timezone: aeroFlight.destination?.timezone ?? null,
    destination_latitude: aeroFlight.destination?.latitude ?? null,
    destination_longitude: aeroFlight.destination?.longitude ?? null,
    aircraft_type: aeroFlight.aircraft_type ?? null,
    registration: aeroFlight.registration ?? null,
    route: aeroFlight.route ?? null,
    scheduled_out: aeroFlight.scheduled_out ?? null,
    scheduled_off: aeroFlight.scheduled_off ?? null,
    scheduled_on: aeroFlight.scheduled_on ?? null,
    scheduled_in: aeroFlight.scheduled_in ?? null,
    estimated_out: aeroFlight.estimated_out ?? null,
    estimated_off: aeroFlight.estimated_off ?? null,
    estimated_on: aeroFlight.estimated_on ?? null,
    estimated_in: aeroFlight.estimated_in ?? null,
    actual_out: aeroFlight.actual_out ?? null,
    actual_off: aeroFlight.actual_off ?? null,
    actual_on: aeroFlight.actual_on ?? null,
    actual_in: aeroFlight.actual_in ?? null,
    departure_delay_seconds: aeroFlight.departure_delay ?? null,
    arrival_delay_seconds: aeroFlight.arrival_delay ?? null,
    // Undocumented fields — tolerate absence gracefully, never fabricate.
    terminal_origin: aeroFlight.terminal_origin ?? null,
    gate_origin: aeroFlight.gate_origin ?? null,
    terminal_destination: aeroFlight.terminal_destination ?? null,
    gate_destination: aeroFlight.gate_destination ?? null,
    baggage_claim: aeroFlight.baggage_claim ?? null,
    cancelled: Boolean(aeroFlight.cancelled),
    diverted: Boolean(aeroFlight.diverted),
    status: deriveFlightStatus(aeroFlight),
  };

  // adsbdb.com route fallback — only when AeroAPI's own response came back with genuinely no
  // route at all on either side (rare). AeroAPI stays the primary/authoritative schedule source;
  // this never overrides a value AeroAPI did provide, and is never called on a normal poll.
  const hasNoOriginCode = !mapped.origin_iata && !mapped.origin_icao;
  const hasNoDestinationCode = !mapped.destination_iata && !mapped.destination_icao;
  if (hasNoOriginCode && hasNoDestinationCode) {
    const callsign = aeroFlight.atc_ident ?? aeroFlight.ident_icao ?? aeroFlight.ident;
    if (callsign) {
      try {
        const route = await fetchRouteFallback(callsign);
        if (route) {
          if (!mapped.airline_name) mapped.airline_name = route.airlineName;
          if (route.origin) {
            mapped.origin_iata = route.origin.iata;
            mapped.origin_icao = route.origin.icao;
            mapped.origin_name = route.origin.name;
            mapped.origin_city = await resolveAirportCity(client, route.origin.iata, route.origin.icao, route.origin.city);
            mapped.origin_latitude = route.origin.latitude;
            mapped.origin_longitude = route.origin.longitude;
          }
          if (route.destination) {
            mapped.destination_iata = route.destination.iata;
            mapped.destination_icao = route.destination.icao;
            mapped.destination_name = route.destination.name;
            mapped.destination_city = await resolveAirportCity(
              client,
              route.destination.iata,
              route.destination.icao,
              route.destination.city,
            );
            mapped.destination_latitude = route.destination.latitude;
            mapped.destination_longitude = route.destination.longitude;
          }
        }
      } catch (err) {
        console.error(`[adsbdb] route fallback threw for ${callsign}:`, (err as Error).message);
      }
    }
  }

  return mapped;
}

// Airport coordinates never change once known, so this only ever looks them up when the
// existing row is still missing them (a one-time backfill per flight, not a per-refresh call).
// Never throws — a lookup failure just leaves the columns null, which the iOS map screen already
// treats as "no marker for this side" per the product brief.
async function backfillAirportCoordinates(
  existing: FlightRow,
  mapped: MappedAeroFields,
): Promise<Partial<Pick<FlightRow, "origin_latitude" | "origin_longitude" | "destination_latitude" | "destination_longitude">>> {
  const patch: Partial<
    Pick<FlightRow, "origin_latitude" | "origin_longitude" | "destination_latitude" | "destination_longitude">
  > = {};

  try {
    if (existing.origin_latitude == null) {
      const code = mapped.origin_icao ?? mapped.origin_iata;
      if (code) {
        const coords = await fetchAirportCoordinates(code);
        if (coords) {
          patch.origin_latitude = coords.latitude;
          patch.origin_longitude = coords.longitude;
        }
      }
    }
  } catch (err) {
    console.error("[flight-sync] origin coordinate backfill threw:", (err as Error).message);
  }

  try {
    if (existing.destination_latitude == null) {
      const code = mapped.destination_icao ?? mapped.destination_iata;
      if (code) {
        const coords = await fetchAirportCoordinates(code);
        if (coords) {
          patch.destination_latitude = coords.latitude;
          patch.destination_longitude = coords.longitude;
        }
      }
    }
  } catch (err) {
    console.error("[flight-sync] destination coordinate backfill threw:", (err as Error).message);
  }

  return patch;
}

interface PendingEvent {
  type:
    | "scheduled"
    | "delay"
    | "gate_change"
    | "terminal_change"
    | "departed"
    | "airborne"
    | "arrival_time_change"
    | "landed"
    | "arrived_at_gate"
    | "baggage_claim"
    | "cancelled"
    | "diverted";
  previous_value: string | null;
  new_value: string | null;
}

function formatDelay(seconds: number): string {
  const mins = Math.round(seconds / 60);
  if (mins < 60) return `${mins} min`;
  const hours = Math.floor(mins / 60);
  const remMins = mins % 60;
  return remMins > 0 ? `${hours}h ${remMins}m` : `${hours}h`;
}

// True when `next` differs from `previous` by at least `thresholdMs` — treats a still-unset
// `previous` (null) as always meaningful (first real estimate is worth an event), but otherwise
// ignores sub-threshold drift between two ISO timestamps that a plain `!==` would still catch.
function hasMeaningfulTimeChange(previous: string | null, next: string, thresholdMs: number): boolean {
  if (!previous) return true;
  const previousMs = Date.parse(previous);
  const nextMs = Date.parse(next);
  if (Number.isNaN(previousMs) || Number.isNaN(nextMs)) return previous !== next;
  return Math.abs(nextMs - previousMs) >= thresholdMs;
}

// Builds the list of flight_status_events to insert by diffing the existing row against the
// freshly-mapped fields. `existing` is null for a brand-new row (handled by add-flight directly,
// not through this diff — add-flight seeds a single "scheduled" event itself).
function diffEvents(existing: FlightRow, mapped: MappedAeroFields): PendingEvent[] {
  const events: PendingEvent[] = [];

  // First real sync after a row is created without a resolved fa_flight_id yet (defensive —
  // add-flight normally resolves fa_flight_id at insert time, but this keeps the pipeline
  // correct if that ever changes).
  if (!existing.fa_flight_id && mapped.fa_flight_id) {
    events.push({ type: "scheduled", previous_value: null, new_value: mapped.scheduled_out });
    return events;
  }

  // AeroAPI re-estimates arrival constantly — a raw inequality check fires on noise as small as
  // a few seconds of re-estimation drift between 5-minute polls, spamming an event + push
  // notification every single tick near departure. Only treat it as a real change worth telling
  // someone about once it's moved by at least a minute, same threshold class as the delay check
  // below. Also stops entirely once the flight has already landed — a confirmed arrival isn't
  // going to move again, so any further "estimated arrival" drift AeroAPI reports past that
  // point is noise, not something worth another push notification for.
  const alreadyLanded = existing.status === "landed" || existing.status === "arrived" || existing.actual_in != null;
  const ARRIVAL_CHANGE_THRESHOLD_MS = 60_000;
  if (!alreadyLanded) {
    if (mapped.scheduled_in && hasMeaningfulTimeChange(existing.scheduled_in, mapped.scheduled_in, ARRIVAL_CHANGE_THRESHOLD_MS)) {
      events.push({ type: "arrival_time_change", previous_value: existing.scheduled_in, new_value: mapped.scheduled_in });
    } else if (mapped.estimated_in && hasMeaningfulTimeChange(existing.estimated_in, mapped.estimated_in, ARRIVAL_CHANGE_THRESHOLD_MS)) {
      events.push({ type: "arrival_time_change", previous_value: existing.estimated_in, new_value: mapped.estimated_in });
    }
  }

  if (mapped.gate_origin && mapped.gate_origin !== existing.gate_origin) {
    events.push({ type: "gate_change", previous_value: existing.gate_origin, new_value: mapped.gate_origin });
  }
  if (mapped.gate_destination && mapped.gate_destination !== existing.gate_destination) {
    events.push({ type: "gate_change", previous_value: existing.gate_destination, new_value: mapped.gate_destination });
  }

  if (mapped.terminal_origin && mapped.terminal_origin !== existing.terminal_origin) {
    events.push({ type: "terminal_change", previous_value: existing.terminal_origin, new_value: mapped.terminal_origin });
  }
  if (mapped.terminal_destination && mapped.terminal_destination !== existing.terminal_destination) {
    events.push({ type: "terminal_change", previous_value: existing.terminal_destination, new_value: mapped.terminal_destination });
  }

  if (mapped.actual_out && !existing.actual_out) {
    events.push({ type: "departed", previous_value: null, new_value: mapped.actual_out });
  }
  if (mapped.actual_off && !existing.actual_off) {
    events.push({ type: "airborne", previous_value: null, new_value: mapped.actual_off });
  }
  if (mapped.actual_on && !existing.actual_on) {
    events.push({ type: "landed", previous_value: null, new_value: mapped.actual_on });
  }
  if (mapped.actual_in && !existing.actual_in) {
    events.push({ type: "arrived_at_gate", previous_value: null, new_value: mapped.actual_in });
  }

  if (mapped.baggage_claim && mapped.baggage_claim !== existing.baggage_claim) {
    events.push({ type: "baggage_claim", previous_value: existing.baggage_claim, new_value: mapped.baggage_claim });
  }

  if (mapped.cancelled && !existing.cancelled) {
    events.push({ type: "cancelled", previous_value: "false", new_value: "true" });
  }
  if (mapped.diverted && !existing.diverted) {
    events.push({ type: "diverted", previous_value: "false", new_value: "true" });
  }

  const prevDepDelay = existing.departure_delay_seconds ?? 0;
  const newDepDelay = mapped.departure_delay_seconds ?? 0;
  if (newDepDelay > 300 && prevDepDelay <= 300) {
    events.push({ type: "delay", previous_value: formatDelay(prevDepDelay), new_value: formatDelay(newDepDelay) });
  }
  const prevArrDelay = existing.arrival_delay_seconds ?? 0;
  const newArrDelay = mapped.arrival_delay_seconds ?? 0;
  if (newArrDelay > 300 && prevArrDelay <= 300 && newDepDelay <= 300) {
    // Only emit a second delay event if it wasn't already covered by the departure-delay check
    // above, to avoid double-notifying for what's effectively the same disruption.
    events.push({ type: "delay", previous_value: formatDelay(prevArrDelay), new_value: formatDelay(newArrDelay) });
  }

  return events;
}

// How long after a flight's best-known arrival it stops being actively tracked (the Trips page's
// "Tracked flights" section drops it, moving it to "Past flights") — shared by the confirmed-
// arrival path below and `reconcileOverdueArrival`'s provider-went-silent fallback, so both count
// down from the same clock.
const ARCHIVE_AFTER_ARRIVAL_MS = 2 * 60 * 60 * 1000;

export async function syncFlight(
  serviceClient: SupabaseClient,
  flightRow: FlightRow,
  aeroFlight: AeroFlight,
  source: "poll" | "webhook",
): Promise<void> {
  const mapped = await mapAeroFlightToRow(serviceClient, aeroFlight);
  const events = diffEvents(flightRow, mapped);

  const update: Record<string, unknown> = { ...mapped, last_refreshed_at: new Date().toISOString() };

  // AeroAPI's regular /flights poll response almost never carries lat/long (only the dedicated
  // /airports/{id} lookup does, see mapAeroFlightToRow's comment above) — mapped.origin_latitude
  // etc. are therefore null on nearly every poll. Coalescing onto the already-known coordinate
  // here (not just when backfill runs) stops a routine poll from clobbering a previously-resolved
  // coordinate back to null, which was making the map flash to its "no route data" fallback and
  // silently dropping the live position marker (avatar/plane) along with it.
  update.origin_latitude = mapped.origin_latitude ?? flightRow.origin_latitude;
  update.origin_longitude = mapped.origin_longitude ?? flightRow.origin_longitude;
  update.destination_latitude = mapped.destination_latitude ?? flightRow.destination_latitude;
  update.destination_longitude = mapped.destination_longitude ?? flightRow.destination_longitude;

  // Same class of bug as the coordinate coalescing above: AeroAPI's poll response doesn't
  // reliably carry gate/terminal/baggage on every single poll, and without this a routine poll
  // that just happened to omit one would clobber the stored value back to null. `diffEvents`
  // above already only *fires an event* for a genuine, truthy value change — but it can't help
  // if the "existing" value it's comparing against next time has been wrongly nulled out in the
  // meantime, since a real (unchanged) value reappearing against a null "existing" reads as a
  // change. This is what was causing "gate/terminal/baggage changed" notifications for a value
  // that never actually changed.
  update.gate_origin = mapped.gate_origin ?? flightRow.gate_origin;
  update.gate_destination = mapped.gate_destination ?? flightRow.gate_destination;
  update.terminal_origin = mapped.terminal_origin ?? flightRow.terminal_origin;
  update.terminal_destination = mapped.terminal_destination ?? flightRow.terminal_destination;
  update.baggage_claim = mapped.baggage_claim ?? flightRow.baggage_claim;
  // Same coalescing reasoning — atc_ident and flight_number_icao are both candidate ADS-B mirror
  // lookup keys (see syncLivePositionForFaFlightId below); a poll that happens to omit either
  // must not clobber a previously-known value back to null. Missing this for flight_number_icao
  // specifically was a real bug: AeroAPI doesn't reliably include ident_icao on every poll, and
  // atc_ident is frequently null for many carriers even once airborne — if a poll nulled out
  // flight_number_icao while atc_ident was already null, both candidates went empty and live
  // position silently stopped updating for that flight until the AeroAPI fallback kicked in
  // after 5 consecutive misses.
  update.atc_ident = mapped.atc_ident ?? flightRow.atc_ident;
  update.flight_number_icao = mapped.flight_number_icao ?? flightRow.flight_number_icao;

  const coordinatePatch = await backfillAirportCoordinates(flightRow, mapped);
  Object.assign(update, coordinatePatch);

  const actualIn = mapped.actual_in ?? flightRow.actual_in;
  if (actualIn && Date.now() - new Date(actualIn).getTime() > ARCHIVE_AFTER_ARRIVAL_MS) {
    update.tracking_enabled = false;
  }

  const { error: updateErr } = await serviceClient.from("flights").update(update).eq("id", flightRow.id);
  if (updateErr) {
    console.error(`[flight-sync] failed to update flight ${flightRow.id}:`, updateErr.message);
    return;
  }

  // Merged locally rather than re-selected — `update` already carries every field that could
  // have changed, so this reflects exactly what was just persisted without an extra round-trip.
  const newRow = { ...flightRow, ...update } as FlightRow;

  if (events.length > 0) {
    const { error: insertErr } = await serviceClient.from("flight_status_events").insert(
      events.map((e) => ({
        flight_id: flightRow.id,
        type: e.type,
        previous_value: e.previous_value,
        new_value: e.new_value,
        source,
      })),
    );
    if (insertErr) {
      console.error(`[flight-sync] failed to insert flight_status_events for ${flightRow.id}:`, insertErr.message);
    }

    for (const event of events) {
      try {
        await notifyForEvent(serviceClient, flightRow.id, { type: event.type, newValue: event.new_value });
      } catch (err) {
        console.error(`[flight-sync] notifyForEvent threw for ${flightRow.id}:`, (err as Error).message);
      }
    }
  }

  try {
    await notifyLiveActivity(serviceClient, flightRow, newRow);
  } catch (err) {
    console.error(`[flight-sync] notifyLiveActivity threw for ${flightRow.id}:`, (err as Error).message);
  }
}

// ---------------------------------------------------------------------------
// Live Activity content-state pushes — a full-snapshot push per sync (not per diffed event,
// since a Live Activity's ContentState is a whole-state replace, not an incremental event).
// Skips sending when nothing Live-Activity-relevant changed, so a no-op poll doesn't spam a
// push. Only called from syncFlight, not syncLivePositionForFaFlightId — live-position pings
// don't affect content-state (progress is time-based off scheduled/estimated/actual times, not
// GPS).
// ---------------------------------------------------------------------------

const LIVE_ACTIVITY_RELEVANT_FIELDS: (keyof FlightRow)[] = [
  "status",
  "scheduled_out",
  "estimated_out",
  "actual_out",
  "scheduled_in",
  "estimated_in",
  "actual_in",
  "gate_origin",
  "gate_destination",
  "terminal_origin",
  "terminal_destination",
  "baggage_claim",
  "departure_delay_seconds",
  "arrival_delay_seconds",
  "cancelled",
  "diverted",
];

const TERMINAL_STATUSES: FlightStatus[] = ["landed", "arrived", "cancelled", "diverted"];

function computeProgress(row: FlightRow): number {
  const isDone = row.status === "arrived" || row.status === "landed";
  const departure = row.actual_out ?? row.estimated_out ?? row.scheduled_out;
  const arrival = row.actual_in ?? row.estimated_in ?? row.scheduled_in;
  if (!departure || !arrival) return isDone ? 1 : 0;

  const dep = new Date(departure).getTime();
  const arr = new Date(arrival).getTime();
  if (arr <= dep) return isDone ? 1 : 0;

  const elapsed = Date.now() - dep;
  return Math.min(1, Math.max(0, elapsed / (arr - dep)));
}

function formatRemaining(ms: number): string {
  const totalSeconds = Math.max(0, Math.round(ms / 1000));
  const days = Math.floor(totalSeconds / 86_400);
  const hours = Math.floor((totalSeconds % 86_400) / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  if (days > 0) return `${days}d ${hours}h`;
  if (hours > 0) return `${hours}h ${minutes}m`;
  return `${minutes}m`;
}

// Mirrors `Flight.countdownSummary` (Swift, in Twofold/Twofold/Models/Flight.swift) — a
// deliberate small duplication so the server can push a label without a round-trip to the
// client; keep the two formulas numerically consistent if either changes.
function computeTimeRemainingLabel(row: FlightRow): string {
  const now = Date.now();
  if (row.status === "cancelled") return "Cancelled";
  if (row.status === "diverted") return "Diverted";

  const arrival = row.actual_in ?? row.estimated_in ?? row.scheduled_in;
  if (row.status === "arrived" || row.status === "landed") {
    return arrival ? `Arrived ${formatRemaining(now - new Date(arrival).getTime())} ago` : "Arrived";
  }

  // "boarding" deliberately excluded here — it means still at the gate, not yet departed, so
  // it falls through to the departure countdown below instead of showing "Arrives in…" for a
  // flight that hasn't taken off yet (same bug/fix as Flight.countdownSummary's Swift mirror).
  if (["landing_soon", "in_air", "departed"].includes(row.status) && arrival) {
    const arrivalMs = new Date(arrival).getTime();
    if (arrivalMs > now) return `Arrives in ${formatRemaining(arrivalMs - now)}`;
  }

  const departure = row.actual_out ?? row.estimated_out ?? row.scheduled_out;
  if (departure) {
    const departureMs = new Date(departure).getTime();
    return departureMs > now ? `Departs in ${formatRemaining(departureMs - now)}` : "Departing shortly";
  }

  return row.status;
}

// Must match JourneyActivityAttributes.ContentState's Swift property names verbatim (default
// Codable camelCase, no CodingKeys) — every Date field goes through toCocoaTimestamp, since
// that's what Swift's default JSONDecoder expects, NOT Unix epoch.
function computeLiveActivityContentState(row: FlightRow, isReunion: boolean): Record<string, unknown> {
  const scheduledDeparture = row.scheduled_out ?? new Date().toISOString();
  const scheduledArrival = row.scheduled_in ?? scheduledDeparture;

  return {
    status: row.status,
    progress: computeProgress(row),
    timeRemainingLabel: computeTimeRemainingLabel(row),
    isReunion,
    scheduledDeparture: toCocoaTimestamp(new Date(scheduledDeparture)),
    scheduledArrival: toCocoaTimestamp(new Date(scheduledArrival)),
    estimatedDeparture: row.estimated_out ? toCocoaTimestamp(new Date(row.estimated_out)) : null,
    estimatedArrival: row.estimated_in ? toCocoaTimestamp(new Date(row.estimated_in)) : null,
    actualDeparture: row.actual_out ? toCocoaTimestamp(new Date(row.actual_out)) : null,
    actualArrival: row.actual_in ? toCocoaTimestamp(new Date(row.actual_in)) : null,
    gateOrigin: row.gate_origin,
    gateDestination: row.gate_destination,
    terminalOrigin: row.terminal_origin,
    terminalDestination: row.terminal_destination,
    baggageClaim: row.baggage_claim,
    departureDelayMinutes: row.departure_delay_seconds != null ? Math.round(row.departure_delay_seconds / 60) : null,
    arrivalDelayMinutes: row.arrival_delay_seconds != null ? Math.round(row.arrival_delay_seconds / 60) : null,
    lastUpdatedAt: toCocoaTimestamp(new Date()),
  };
}

async function notifyLiveActivity(serviceClient: SupabaseClient, oldRow: FlightRow, newRow: FlightRow): Promise<void> {
  const changed = LIVE_ACTIVITY_RELEVANT_FIELDS.some((field) => oldRow[field] !== newRow[field]);
  const becameTerminal = !TERMINAL_STATUSES.includes(oldRow.status) && TERMINAL_STATUSES.includes(newRow.status);
  if (!changed && !becameTerminal) return;

  const { data: tokens, error } = await serviceClient
    .from("live_activity_push_tokens")
    .select("id, profile_id, activity_id, push_token, environment")
    .eq("flight_id", newRow.id);
  if (error || !tokens || tokens.length === 0) return;

  for (const token of tokens) {
    try {
      const isReunion = token.profile_id !== newRow.created_by;
      const contentState = computeLiveActivityContentState(newRow, isReunion);

      if (becameTerminal) {
        const arrivalBasis = newRow.actual_in ?? newRow.estimated_in ?? newRow.scheduled_in;
        const dismissalDateUnix = Math.round(
          (arrivalBasis ? new Date(arrivalBasis).getTime() : Date.now()) / 1000,
        ) + 30 * 60;
        await sendLiveActivityUpdate(token.push_token, token.environment, contentState, "end", { dismissalDateUnix });
        await serviceClient.from("live_activity_push_tokens").delete().eq("id", token.id);
      } else {
        await sendLiveActivityUpdate(token.push_token, token.environment, contentState, "update");
      }
    } catch (err) {
      console.error(`[flight-sync] notifyLiveActivity threw for token ${token.id}:`, (err as Error).message);
    }
  }
}

// Statuses where a live position is worth fetching — airborne-ish states. Exported so
// refresh-flight can gate its own immediate, user-triggered syncLivePositionForFaFlightId call
// the same way syncLivePositions does.
export const AIRBORNE_STATUSES: FlightStatus[] = ["departed", "in_air", "landing_soon"];

// ---------------------------------------------------------------------------
// Deduped, ADS-B-sourced live position. One `flight_live_positions` cache row per real-world
// flight (keyed by fa_flight_id, AeroAPI's own canonical per-instance id — shared across every
// couple independently tracking the same flight), so N couples watching the same flight produce
// exactly one mirror fetch per cache window instead of N. See
// supabase/migrations/20260829000000_flight_live_positions.sql.
// ---------------------------------------------------------------------------

const LIVE_POSITION_CACHE_TTL_MS = 55_000; // just under the 1-minute cron cadence
const ADSB_FAILURE_FALLBACK_THRESHOLD = 5; // consecutive misses before trying the paid AeroAPI fallback
const AEROAPI_FALLBACK_TTL_MS = 2 * 60 * 1000; // don't hammer the paid endpoint even as a fallback

interface FlightLivePositionRow {
  fa_flight_id: string;
  atc_ident: string | null;
  hex: string | null;
  query_key: string | null;
  source: string | null;
  latitude: number | null;
  longitude: number | null;
  altitude: number | null;
  groundspeed: number | null;
  heading: number | null;
  consecutive_failures: number;
  fetched_at: string | null;
  updated_at: string;
}

// Deduped by fa_flight_id, not by couple/flight-row id — this is the actual dedup payoff. Never
// throws: an ADS-B (or even AeroAPI-fallback) failure here must never block the caller's own
// AeroAPI schedule/status refresh, which is what notifications/Live Activity actually depend on.
export async function syncLivePositionForFaFlightId(
  serviceClient: SupabaseClient,
  faFlightId: string,
  candidates: string[],
): Promise<void> {
  const { data: cached } = await serviceClient
    .from("flight_live_positions")
    .select("*")
    .eq("fa_flight_id", faFlightId)
    .maybeSingle();

  const cachedRow = cached as FlightLivePositionRow | null;
  const isFresh = Boolean(
    cachedRow?.fetched_at && Date.now() - new Date(cachedRow.fetched_at).getTime() < LIVE_POSITION_CACHE_TTL_MS,
  );

  let row = cachedRow;

  if (!isFresh) {
    const hit = candidates.length > 0 ? await fetchLivePosition(candidates) : null;

    if (hit) {
      const { data: upserted, error } = await serviceClient
        .from("flight_live_positions")
        .upsert(
          {
            fa_flight_id: faFlightId,
            atc_ident: candidates[0] ?? null,
            hex: hit.position.hex,
            query_key: hit.candidateIndex === 0 ? "atc_ident" : "icao_fallback",
            source: hit.source,
            latitude: hit.position.latitude,
            longitude: hit.position.longitude,
            altitude: hit.position.altitude,
            groundspeed: hit.position.groundspeed,
            heading: hit.position.heading,
            consecutive_failures: 0,
            fetched_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
          },
          { onConflict: "fa_flight_id" },
        )
        .select()
        .single();
      if (error) {
        console.error(`[adsb] failed to upsert flight_live_positions for ${faFlightId}:`, error.message);
      } else {
        row = upserted as FlightLivePositionRow;
      }
    } else {
      // Every mirror/candidate missed this cycle. Track consecutive misses so a flight that's
      // genuinely gone dark (e.g. an oceanic leg outside terrestrial ADS-B receiver coverage) can
      // fall back to AeroAPI's paid position endpoint — rate-limited, and still funneled through
      // this same fa_flight_id-deduped cache, so it stays a strict improvement over the old
      // zero-dedup baseline even in the fallback case.
      const failures = (cachedRow?.consecutive_failures ?? 0) + 1;
      const aeroApiFallbackStale = !cachedRow?.fetched_at || cachedRow.source !== "aeroapi_fallback" ||
        Date.now() - new Date(cachedRow.fetched_at).getTime() >= AEROAPI_FALLBACK_TTL_MS;

      let fallbackRow: FlightLivePositionRow | null = null;
      if (failures >= ADSB_FAILURE_FALLBACK_THRESHOLD && aeroApiFallbackStale) {
        try {
          const position = await fetchPosition(faFlightId);
          if (position) {
            const { data: upserted, error } = await serviceClient
              .from("flight_live_positions")
              .upsert(
                {
                  fa_flight_id: faFlightId,
                  hex: null,
                  query_key: "aeroapi_fallback",
                  source: "aeroapi_fallback",
                  latitude: position.latitude,
                  longitude: position.longitude,
                  altitude: position.altitude ?? null,
                  groundspeed: position.groundspeed ?? null,
                  heading: position.heading ?? null,
                  consecutive_failures: 0,
                  fetched_at: new Date().toISOString(),
                  updated_at: new Date().toISOString(),
                },
                { onConflict: "fa_flight_id" },
              )
              .select()
              .single();
            if (error) {
              console.error(`[adsb] failed to upsert AeroAPI fallback position for ${faFlightId}:`, error.message);
            } else {
              fallbackRow = upserted as FlightLivePositionRow;
            }
          }
        } catch (err) {
          console.error(`[adsb] AeroAPI position fallback threw for ${faFlightId}:`, (err as Error).message);
        }
      }

      if (fallbackRow) {
        row = fallbackRow;
      } else {
        // Record the miss so consecutive_failures accumulates toward the fallback threshold,
        // without touching the last-known position — still the best data available to show.
        await serviceClient
          .from("flight_live_positions")
          .upsert(
            { fa_flight_id: faFlightId, consecutive_failures: failures, updated_at: new Date().toISOString() },
            { onConflict: "fa_flight_id" },
          );
      }
    }
  }

  if (!row || row.latitude == null || row.longitude == null) return; // never had a fix yet

  // The dedup payoff: one update, filtered by fa_flight_id (not a single row id), broadcasts to
  // every couple's flights row tracking this same real-world flight.
  const { error } = await serviceClient
    .from("flights")
    .update({
      position_latitude: row.latitude,
      position_longitude: row.longitude,
      position_altitude: row.altitude,
      position_groundspeed: row.groundspeed,
      position_heading: row.heading,
      position_updated_at: row.fetched_at ?? new Date().toISOString(),
    })
    .eq("fa_flight_id", faFlightId)
    .eq("tracking_enabled", true);
  if (error) {
    console.error(`[adsb] failed to broadcast position onto flights for ${faFlightId}:`, error.message);
  }
}

// Called once per refresh-due-flights cron tick (every minute), independent of isDue()'s
// AeroAPI-staleness tiering — that tiering exists to space out paid AeroAPI schedule calls, but
// live position from free mirrors has no such cost pressure and refreshes flat, every tick, for
// every currently-airborne flight. Deduped by fa_flight_id: two couples tracking the same
// real-world flight collapse into a single syncLivePositionForFaFlightId call.
export async function syncLivePositions(serviceClient: SupabaseClient, activeCoupleIds: string[]): Promise<void> {
  if (activeCoupleIds.length === 0) return;

  const { data: flights, error } = await serviceClient
    .from("flights")
    .select("fa_flight_id, atc_ident, flight_number_icao")
    .eq("tracking_enabled", true)
    .in("couple_id", activeCoupleIds)
    .in("status", AIRBORNE_STATUSES)
    .not("fa_flight_id", "is", null);

  if (error) {
    console.error("[adsb] failed to load airborne flights for live-position sync:", error.message);
    return;
  }

  type Candidate = { fa_flight_id: string; atc_ident: string | null; flight_number_icao: string | null };
  const byFaFlightId = new Map<string, Candidate>();
  for (const flight of (flights ?? []) as Candidate[]) {
    if (!byFaFlightId.has(flight.fa_flight_id)) byFaFlightId.set(flight.fa_flight_id, flight);
  }

  for (const [faFlightId, flight] of byFaFlightId) {
    const candidates = [flight.atc_ident, flight.flight_number_icao].filter((v): v is string => Boolean(v));
    try {
      await syncLivePositionForFaFlightId(serviceClient, faFlightId, candidates);
    } catch (err) {
      console.error(`[adsb] syncLivePositionForFaFlightId threw for ${faFlightId}:`, (err as Error).message);
    }
  }
}

// Fetches fresh data for one already-resolved flight and runs it through syncFlight, then
// returns the updated row. Shared by refresh-flight (single flight, user-triggered) and
// refresh-due-flights (cron, many flights) so the fetch+sync logic only lives once.
export async function refreshOneFlight(serviceClient: SupabaseClient, flightRow: FlightRow): Promise<FlightRow | null> {
  if (!flightRow.fa_flight_id) {
    console.error(`[flight-sync] flight ${flightRow.id} has no fa_flight_id, cannot refresh`);
    return flightRow;
  }

  const aeroFlight = await fetchFlightByFaId(flightRow.fa_flight_id);
  if (!aeroFlight) {
    console.error(`[flight-sync] AeroAPI returned no flight for fa_flight_id ${flightRow.fa_flight_id}`);
    return flightRow;
  }

  await syncFlight(serviceClient, flightRow, aeroFlight, "poll");

  // Live position is deliberately NOT synced inline here anymore — it now runs as its own pass,
  // deduped by fa_flight_id across every couple tracking the same real-world flight, flat every
  // cron tick regardless of this row's own AeroAPI schedule-tier staleness. See
  // syncLivePositions() (called from refresh-due-flights after its main loop) and
  // syncLivePositionForFaFlightId() (called directly by refresh-flight for an immediate,
  // user-triggered refresh).

  const { data: updated } = await serviceClient.from("flights").select("*").eq("id", flightRow.id).single();
  return (updated as FlightRow) ?? flightRow;
}

// How long past a flight's best-known arrival time with no actual_in/actual_on confirmation
// before assuming it landed anyway. AeroAPI's /flights/{id} lookup can go permanently silent on
// an old flight (confirmed live: a tracked flight got stuck at "landing_soon" for 7+ hours,
// last_refreshed_at frozen, despite refresh-due-flights attempting a refresh on every single
// 5-minute cron tick) — deriveFlightStatus() only ever reaches "landed"/"arrived" from actual_on/
// actual_in, so without this fallback a flight the provider goes quiet on is stuck forever,
// visibly wrong (still says "Landing soon") and never eligible to archive.
const ARRIVAL_STATUS_OVERDUE_MS = 90 * 60 * 1000;

function bestKnownArrivalMs(flight: FlightRow): number | null {
  const arrival = flight.actual_in ?? flight.estimated_in ?? flight.scheduled_in;
  return arrival ? new Date(arrival).getTime() : null;
}

// Called for every actively-tracked, non-terminal flight on every refresh-due-flights tick
// (independent of isDue()'s own AeroAPI-refresh cadence, and also from refresh-flight's
// user-triggered path) — a flight the provider has gone silent on still needs to be reconciled
// even on ticks where a real API call isn't due. Two independent, additive effects:
//   1. Past ARRIVAL_STATUS_OVERDUE_MS since best-known arrival with no confirmed actual_in/
//      actual_on: force status to "arrived" locally, and notify same as a normal landing would.
//   2. Past ARCHIVE_AFTER_ARRIVAL_MS since arrival (confirmed or just forced above): disable
//      tracking_enabled, same threshold `syncFlight` already uses for a confirmed actual_in.
export async function reconcileOverdueArrival(serviceClient: SupabaseClient, flight: FlightRow, now: number): Promise<void> {
  if (!flight.tracking_enabled || flight.status === "cancelled" || flight.status === "diverted") return;
  const arrivalMs = bestKnownArrivalMs(flight);
  if (arrivalMs === null) return;

  let currentStatus = flight.status;
  const wasTerminal = currentStatus === "arrived" || currentStatus === "landed";

  if (!wasTerminal && now - arrivalMs > ARRIVAL_STATUS_OVERDUE_MS) {
    const { error } = await serviceClient.from("flights").update({ status: "arrived" }).eq("id", flight.id);
    if (error) {
      console.error(`[flight-sync] failed to mark overdue flight ${flight.id} arrived:`, error.message);
      return;
    }
    currentStatus = "arrived";

    const arrivalIso = flight.estimated_in ?? flight.scheduled_in;
    const { error: insertErr } = await serviceClient.from("flight_status_events").insert({
      flight_id: flight.id,
      type: "arrived_at_gate",
      previous_value: null,
      new_value: arrivalIso,
      source: "poll",
    });
    if (insertErr) {
      console.error(`[flight-sync] failed to insert overdue-arrival event for ${flight.id}:`, insertErr.message);
    }

    try {
      await notifyForEvent(serviceClient, flight.id, { type: "arrived_at_gate", newValue: arrivalIso });
    } catch (err) {
      console.error(`[flight-sync] notifyForEvent threw for overdue arrival ${flight.id}:`, (err as Error).message);
    }
    try {
      await notifyLiveActivity(serviceClient, flight, { ...flight, status: "arrived" });
    } catch (err) {
      console.error(`[flight-sync] notifyLiveActivity threw for overdue arrival ${flight.id}:`, (err as Error).message);
    }
  }

  const isNowTerminal = wasTerminal || currentStatus === "arrived";
  if (isNowTerminal && now - arrivalMs > ARCHIVE_AFTER_ARRIVAL_MS) {
    const { error } = await serviceClient.from("flights").update({ tracking_enabled: false }).eq("id", flight.id);
    if (error) console.error(`[flight-sync] failed to archive flight ${flight.id}:`, error.message);
  }
}

// Best-effort weather refresh — only called from refresh-due-flights (not from every user-
// triggered refresh, to keep AeroAPI call volume down). Never throws.
export async function maybeRefreshWeather(serviceClient: SupabaseClient, flightRow: FlightRow): Promise<void> {
  const staleThresholdMs = 2 * 60 * 60 * 1000;
  const isStale = !flightRow.weather_updated_at ||
    Date.now() - new Date(flightRow.weather_updated_at).getTime() > staleThresholdMs;
  if (!isStale) return;

  try {
    const [weatherOrigin, weatherDestination] = await Promise.all([
      flightRow.origin_iata || flightRow.origin_icao
        ? fetchAirportWeather(flightRow.origin_iata ?? flightRow.origin_icao!)
        : Promise.resolve(null),
      flightRow.destination_iata || flightRow.destination_icao
        ? fetchAirportWeather(flightRow.destination_iata ?? flightRow.destination_icao!)
        : Promise.resolve(null),
    ]);

    const { error } = await serviceClient
      .from("flights")
      .update({
        weather_origin: weatherOrigin,
        weather_destination: weatherDestination,
        weather_updated_at: new Date().toISOString(),
      })
      .eq("id", flightRow.id);
    if (error) console.error(`[flight-sync] failed to store weather for ${flightRow.id}:`, error.message);
  } catch (err) {
    console.error(`[flight-sync] weather refresh threw for ${flightRow.id}:`, (err as Error).message);
  }
}
