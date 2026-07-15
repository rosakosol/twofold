// Fans a single flight_status_events row out to push notifications for whichever partner(s)
// have opted into that event type. Called from flight-sync.ts after a sync detects a change —
// never called directly from a client. Always best-effort from the caller's point of view: every
// DB read/send here is wrapped so a notification problem never breaks a sync.

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { sendAPNs } from "./apns.ts";

export interface FlightEvent {
  type: string;
  newValue?: string | null;
}

// Event type -> flight_notification_preferences column. Event types with no entry here (e.g.
// the initial "scheduled" baseline) are never pushed.
const PREFERENCE_COLUMN: Record<string, string> = {
  gate_change: "gate_terminal_changes",
  terminal_change: "gate_terminal_changes",
  delay: "delay_or_cancellation",
  cancelled: "delay_or_cancellation",
  diverted: "delay_or_cancellation",
  departed: "departure",
  airborne: "departure",
  arrival_time_change: "landing",
  landed: "landing",
  arrived_at_gate: "arrival_at_gate",
  baggage_claim: "baggage_claim_update",
};

// `newValue` for arrival_time_change is a raw ISO8601 instant from the server — format it as a
// readable local time (destination airport's zone when known) rather than pushing the raw
// timestamp string straight to someone's lock screen.
function formatArrivalTime(iso: string, timeZone: string | null): string {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return iso;
  try {
    return new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit", timeZone: timeZone ?? undefined }).format(date);
  } catch {
    return new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit" }).format(date);
  }
}

// Mirrors `Flight.displayNumber` on the client — prefixes the airline code onto the number
// unless it's already there (AeroAPI sometimes includes it, sometimes doesn't).
function displayFlightNumber(flightNumberIATA: string | null, airlineCode: string | null): string {
  if (!flightNumberIATA) return "Flight";
  if (airlineCode && !flightNumberIATA.startsWith(airlineCode)) return `${airlineCode}${flightNumberIATA}`;
  return flightNumberIATA;
}

// Every push needs to say *whose* flight this is about, never a generic "Their" — the
// traveler's first name plus the flight number when exactly one traveler is set. With zero
// travelers (unknown) or both partners travelling together, a possessive reads oddly ("Alice &
// Bob's UA123" going out to Alice and Bob about their own shared flight) — just the flight
// number in both of those cases.
function flightLabel(travelerNames: string[], flightNumberIATA: string | null, airlineCode: string | null): string {
  const number = displayFlightNumber(flightNumberIATA, airlineCode);
  return travelerNames.length === 1 ? `${travelerNames[0]}'s ${number}` : number;
}

function buildMessage(event: FlightEvent, label: string, destinationTimezone: string | null): { title: string; body: string } {
  const v = event.newValue ?? undefined;
  switch (event.type) {
    case "gate_change":
      return { title: "Gate changed", body: v ? `${label}: departure gate changed to ${v}.` : `${label}: departure gate changed.` };
    case "terminal_change":
      return { title: "Terminal changed", body: v ? `${label}: terminal changed to ${v}.` : `${label}: terminal changed.` };
    case "delay":
      return { title: "Flight delayed", body: v ? `${label} is now delayed by ${v}.` : `${label} is now delayed.` };
    case "cancelled":
      return { title: "Flight cancelled", body: `${label} has been cancelled.` };
    case "diverted":
      return { title: "Flight diverted", body: `${label} has been diverted.` };
    case "departed":
      return { title: "Flight departed", body: `${label} has departed.` };
    case "airborne":
      return { title: "Flight airborne", body: `${label} is now in the air.` };
    case "arrival_time_change":
      return { title: "Arrival time updated", body: v ? `New estimated arrival for ${label}: ${formatArrivalTime(v, destinationTimezone)}.` : `${label}: estimated arrival time changed.` };
    case "landed":
      return { title: "Flight landed", body: `${label} has landed.` };
    case "arrived_at_gate":
      return { title: "Arrived at gate", body: `${label} has arrived at the gate.` };
    case "baggage_claim":
      return { title: "Baggage claim assigned", body: v ? `${label}: baggage claim ${v}.` : `${label}: baggage claim has been assigned.` };
    default:
      return { title: "Flight update", body: v ?? `${label}: flight status changed.` };
  }
}

export async function notifyForEvent(
  serviceClient: SupabaseClient,
  flightId: string,
  event: FlightEvent,
): Promise<void> {
  const prefColumn = PREFERENCE_COLUMN[event.type];
  if (!prefColumn) return; // not a push-worthy event type (e.g. the initial "scheduled" baseline)

  const { data: flight, error: flightErr } = await serviceClient
    .from("flights")
    .select("couple_id, destination_timezone, shared, created_by, traveler_ids, flight_number_iata, airline_code")
    .eq("id", flightId)
    .single();
  if (flightErr || !flight) return;

  const travelerIds: string[] = flight.traveler_ids ?? [];
  let travelerNames: string[] = [];
  if (travelerIds.length > 0) {
    const { data: travelers } = await serviceClient
      .from("profiles")
      .select("first_name")
      .in("id", travelerIds);
    travelerNames = (travelers ?? [])
      .map((t: { first_name: string | null }) => t.first_name)
      .filter((name: string | null): name is string => Boolean(name));
  }
  const label = flightLabel(travelerNames, flight.flight_number_iata ?? null, flight.airline_code ?? null);

  // This runs under the service-role client (RLS-bypassing), so a private (shared: false)
  // flight needs its own explicit check here — otherwise the creator's partner would still get
  // pushed a notification about a flight they can't even see in the app.
  let partnerIds: string[];
  if (flight.shared === false) {
    if (!flight.created_by) return;
    partnerIds = [flight.created_by as string];
  } else {
    const { data: couple, error: coupleErr } = await serviceClient
      .from("couples")
      .select("partner_a_id, partner_b_id")
      .eq("id", flight.couple_id)
      .single();
    if (coupleErr || !couple) return;
    partnerIds = [couple.partner_a_id, couple.partner_b_id].filter((id): id is string => Boolean(id));
  }
  if (partnerIds.length === 0) return;

  const { data: prefRows } = await serviceClient
    .from("flight_notification_preferences")
    .select(`profile_id, ${prefColumn}`)
    .eq("flight_id", flightId)
    .in("profile_id", partnerIds);

  const prefByProfile = new Map<string, boolean>();
  for (const row of prefRows ?? []) {
    prefByProfile.set((row as any).profile_id, Boolean((row as any)[prefColumn]));
  }

  // No preference row yet defaults to "notify" (matches the table's own column defaults).
  const allowedPartnerIds = partnerIds.filter((id) => prefByProfile.get(id) ?? true);
  if (allowedPartnerIds.length === 0) return;

  const { data: tokens } = await serviceClient
    .from("device_push_tokens")
    .select("apns_token, environment")
    .in("profile_id", allowedPartnerIds);
  if (!tokens || tokens.length === 0) return;

  const { title, body } = buildMessage(event, label, (flight as { destination_timezone?: string | null }).destination_timezone ?? null);

  for (const token of tokens) {
    try {
      await sendAPNs(token.apns_token, token.environment, title, body);
    } catch (err) {
      console.error("[notify] sendAPNs threw:", (err as Error).message);
    }
  }
}

// Time-based reminder, not a flight_status_events diff like notifyForEvent above — called from
// refresh-due-flights once a flight is within ~10 minutes of departure and hasn't actually left
// yet (see FLIGHT_ROW columns pre_departure_notified/actual_out). Goes to the *other* partner
// only, never the traveler themselves — reuses the "departure" preference column rather than
// adding a new one, since this is conceptually the same notification category.
export async function notifyPreDeparture(
  serviceClient: SupabaseClient,
  flightId: string,
): Promise<void> {
  const { data: flight, error: flightErr } = await serviceClient
    .from("flights")
    .select("couple_id, shared, created_by, traveler_ids, flight_number_iata, airline_code")
    .eq("id", flightId)
    .single();
  const travelerIds: string[] = flight?.traveler_ids ?? [];
  if (flightErr || !flight || travelerIds.length === 0) return; // no known traveler — "wish them" wouldn't mean anything

  // Only meaningful when there's exactly one traveler — with both partners travelling, every
  // couple member is a traveler, `recipientIds` below ends up empty, and this reminder no-ops
  // (there's no "other partner" left to wish them a safe flight).
  let travelerName: string | null = null;
  if (travelerIds.length === 1) {
    const { data: traveler } = await serviceClient
      .from("profiles")
      .select("first_name")
      .eq("id", travelerIds[0])
      .single();
    travelerName = traveler?.first_name || null;
  }

  // A private (shared: false) flight has no partner who can even see it — nothing to notify.
  if (flight.shared === false) return;

  const { data: couple, error: coupleErr } = await serviceClient
    .from("couples")
    .select("partner_a_id, partner_b_id")
    .eq("id", flight.couple_id)
    .single();
  if (coupleErr || !couple) return;

  const recipientIds = [couple.partner_a_id, couple.partner_b_id]
    .filter((id): id is string => Boolean(id))
    .filter((id) => !travelerIds.includes(id));
  if (recipientIds.length === 0) return;

  const { data: prefRows } = await serviceClient
    .from("flight_notification_preferences")
    .select("profile_id, departure")
    .eq("flight_id", flightId)
    .in("profile_id", recipientIds);

  const prefByProfile = new Map<string, boolean>();
  for (const row of prefRows ?? []) {
    prefByProfile.set((row as any).profile_id, Boolean((row as any).departure));
  }
  const allowedIds = recipientIds.filter((id) => prefByProfile.get(id) ?? true);
  if (allowedIds.length === 0) return;

  const { data: tokens } = await serviceClient
    .from("device_push_tokens")
    .select("apns_token, environment")
    .in("profile_id", allowedIds);
  if (!tokens || tokens.length === 0) return;

  const label = flightLabel(travelerName ? [travelerName] : [], flight.flight_number_iata ?? null, flight.airline_code ?? null);
  const title = "Wheels up soon";
  const body = travelerName
    ? `${label} departs in about 10 minutes. Wish ${travelerName} a safe flight! ✈️`
    : `${label} departs in about 10 minutes. Wish them a safe flight! ✈️`;

  for (const token of tokens) {
    try {
      await sendAPNs(token.apns_token, token.environment, title, body);
    } catch (err) {
      console.error("[notify] sendAPNs threw (pre-departure):", (err as Error).message);
    }
  }
}
