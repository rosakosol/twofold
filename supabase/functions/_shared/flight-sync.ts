// The single shared diff/persist routine for flight data. Both the polling paths
// (refresh-flight, refresh-due-flights) and the webhook path (aeroapi-webhook) call syncFlight()
// so a given change is only ever detected, persisted, and notified-about once, in one place.

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import {
  type AeroFlight,
  type AeroPosition,
  fetchAirportCoordinates,
  fetchAirportWeather,
  fetchFlightByFaId,
  fetchPosition,
} from "./aeroapi.ts";
import { lookupAirlineName } from "./airlines.ts";
import { deriveFlightStatus, type FlightStatus } from "./flight-status.ts";
import { notifyForEvent } from "./notify.ts";

// Mirrors supabase/migrations/20260712000000_flight_tracking.sql's `flights` table exactly.
export interface FlightRow {
  id: string;
  trip_id: string | null;
  couple_id: string;
  created_by: string | null;
  fa_flight_id: string | null;
  flight_number_iata: string | null;
  flight_number_icao: string | null;
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
}

// Fields sourced directly from an AeroFlight, shared by add-flight's initial insert and
// flight-sync's per-refresh update. Deliberately excludes columns owned by other flows
// (id/couple_id/trip_id/created_by, position_*, weather_*, tracking_enabled).
export type MappedAeroFields = Pick<
  FlightRow,
  | "fa_flight_id"
  | "flight_number_iata"
  | "flight_number_icao"
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

export function mapAeroFlightToRow(aeroFlight: AeroFlight): MappedAeroFields {
  return {
    fa_flight_id: aeroFlight.fa_flight_id ?? null,
    flight_number_iata: aeroFlight.ident_iata ?? aeroFlight.ident ?? null,
    flight_number_icao: aeroFlight.ident_icao ?? null,
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
    origin_city: aeroFlight.origin?.city ?? null,
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
    destination_city: aeroFlight.destination?.city ?? null,
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

  if (mapped.scheduled_in && mapped.scheduled_in !== existing.scheduled_in) {
    events.push({ type: "arrival_time_change", previous_value: existing.scheduled_in, new_value: mapped.scheduled_in });
  } else if (mapped.estimated_in && mapped.estimated_in !== existing.estimated_in) {
    events.push({ type: "arrival_time_change", previous_value: existing.estimated_in, new_value: mapped.estimated_in });
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

export async function syncFlight(
  serviceClient: SupabaseClient,
  flightRow: FlightRow,
  aeroFlight: AeroFlight,
  source: "poll" | "webhook",
): Promise<void> {
  const mapped = mapAeroFlightToRow(aeroFlight);
  const events = diffEvents(flightRow, mapped);

  const update: Record<string, unknown> = { ...mapped, last_refreshed_at: new Date().toISOString() };

  const coordinatePatch = await backfillAirportCoordinates(flightRow, mapped);
  Object.assign(update, coordinatePatch);

  const actualIn = mapped.actual_in ?? flightRow.actual_in;
  if (actualIn && Date.now() - new Date(actualIn).getTime() > 30 * 60 * 1000) {
    update.tracking_enabled = false;
  }

  const { error: updateErr } = await serviceClient.from("flights").update(update).eq("id", flightRow.id);
  if (updateErr) {
    console.error(`[flight-sync] failed to update flight ${flightRow.id}:`, updateErr.message);
    return;
  }

  if (events.length === 0) return;

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

// Statuses where a live position is worth fetching — airborne-ish states.
const AIRBORNE_STATUSES: FlightStatus[] = ["departed", "in_air", "landing_soon"];

async function applyPosition(serviceClient: SupabaseClient, flightId: string, position: AeroPosition): Promise<void> {
  const { error } = await serviceClient
    .from("flights")
    .update({
      position_latitude: position.latitude,
      position_longitude: position.longitude,
      position_altitude: position.altitude ?? null,
      position_groundspeed: position.groundspeed ?? null,
      position_heading: position.heading ?? null,
      position_updated_at: position.timestamp ?? new Date().toISOString(),
    })
    .eq("id", flightId);
  if (error) {
    console.error(`[flight-sync] failed to apply position for ${flightId}:`, error.message);
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

  const status = deriveFlightStatus(aeroFlight);
  if (AIRBORNE_STATUSES.includes(status)) {
    try {
      const position = await fetchPosition(flightRow.fa_flight_id);
      if (position) await applyPosition(serviceClient, flightRow.id, position);
    } catch (err) {
      console.error(`[flight-sync] fetchPosition threw for ${flightRow.id}:`, (err as Error).message);
    }
  }

  const { data: updated } = await serviceClient.from("flights").select("*").eq("id", flightRow.id).single();
  return (updated as FlightRow) ?? flightRow;
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
