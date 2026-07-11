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

function buildMessage(event: FlightEvent): { title: string; body: string } {
  const v = event.newValue ?? undefined;
  switch (event.type) {
    case "gate_change":
      return { title: "Gate changed", body: v ? `Their departure gate changed to ${v}.` : "Their departure gate changed." };
    case "terminal_change":
      return { title: "Terminal changed", body: v ? `Their terminal changed to ${v}.` : "Their terminal changed." };
    case "delay":
      return { title: "Flight delayed", body: v ? `Their flight is now delayed by ${v}.` : "Their flight is now delayed." };
    case "cancelled":
      return { title: "Flight cancelled", body: "Their flight has been cancelled." };
    case "diverted":
      return { title: "Flight diverted", body: "Their flight has been diverted." };
    case "departed":
      return { title: "Flight departed", body: "Their flight has departed." };
    case "airborne":
      return { title: "Flight airborne", body: "Their flight is now in the air." };
    case "arrival_time_change":
      return { title: "Arrival time updated", body: v ? `Their new estimated arrival is ${v}.` : "Their estimated arrival time changed." };
    case "landed":
      return { title: "Flight landed", body: "Their flight has landed." };
    case "arrived_at_gate":
      return { title: "Arrived at gate", body: "Their flight has arrived at the gate." };
    case "baggage_claim":
      return { title: "Baggage claim assigned", body: v ? `Baggage claim ${v}.` : "Baggage claim has been assigned." };
    default:
      return { title: "Flight update", body: v ?? "Their flight status changed." };
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
    .select("couple_id")
    .eq("id", flightId)
    .single();
  if (flightErr || !flight) return;

  const { data: couple, error: coupleErr } = await serviceClient
    .from("couples")
    .select("partner_a_id, partner_b_id")
    .eq("id", flight.couple_id)
    .single();
  if (coupleErr || !couple) return;

  const partnerIds = [couple.partner_a_id, couple.partner_b_id].filter((id): id is string => Boolean(id));
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

  const { title, body } = buildMessage(event);

  for (const token of tokens) {
    try {
      await sendAPNs(token.apns_token, token.environment, title, body);
    } catch (err) {
      console.error("[notify] sendAPNs threw:", (err as Error).message);
    }
  }
}
