// Starts tracking a flight the caller has already confirmed via resolve-flight. Re-fetches the
// flight fresh from AeroAPI by fa_flight_id (never trusts client-supplied flight fields), inserts
// the `flights` row and its baseline "scheduled" event using the service role key (flights/
// flight_status_events have no client write policy by design — see the migration), creates
// default notification preference rows for both partners, and best-effort registers an AeroAPI
// alert so future changes arrive over the webhook in addition to polling.
//
// Requires an `Authorization: Bearer <user access token>` header (the caller's Supabase auth
// session) so we can resolve which couple this flight belongs to.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { createAlert, fetchAirportCoordinates, fetchFlightByFaId } from "../_shared/aeroapi.ts";
import { deriveFlightStatus } from "../_shared/flight-status.ts";
import { mapAeroFlightToRow } from "../_shared/flight-sync.ts";

interface Input {
  faFlightId: string;
  tripId?: string;
  travelerId?: string;
  notifyMe: boolean;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405 });
  }

  let input: Input;
  try {
    input = await req.json();
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  if (!input?.faFlightId || typeof input.faFlightId !== "string") {
    return Response.json({ error: "'faFlightId' is required" }, { status: 400 });
  }
  if (typeof input.notifyMe !== "boolean") {
    return Response.json({ error: "'notifyMe' is required" }, { status: 400 });
  }

  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
  );

  const { data: { user } } = await userClient.auth.getUser();
  if (!user) {
    return Response.json({ error: "Not authenticated" }, { status: 401 });
  }

  const { data: couple, error: coupleErr } = await userClient
    .from("couples")
    .select("id, partner_a_id, partner_b_id")
    .or(`partner_a_id.eq.${user.id},partner_b_id.eq.${user.id}`)
    .eq("status", "active")
    .maybeSingle();
  if (coupleErr || !couple) {
    return Response.json({ error: "No active couple for this user" }, { status: 403 });
  }

  // Only allow tagging a traveler who's actually a member of this couple — never trust an
  // arbitrary client-supplied uuid for a column other users' UIs will render as "so-and-so's
  // journey." Compared lowercase: Swift's `UUID.uuidString` is uppercase, but Postgres always
  // returns uuid columns lowercase — a case-sensitive `!==` here fails for every real traveler.
  const travelerId = input.travelerId?.toLowerCase();
  if (travelerId && travelerId !== couple.partner_a_id?.toLowerCase() && travelerId !== couple.partner_b_id?.toLowerCase()) {
    return Response.json({ error: "'travelerId' must be a member of this couple" }, { status: 400 });
  }

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  let aeroFlight;
  try {
    aeroFlight = await fetchFlightByFaId(input.faFlightId);
  } catch (err) {
    console.error("[add-flight] AeroAPI lookup failed:", (err as Error).message);
    return Response.json({ error: "Flight lookup failed, please try again" }, { status: 502 });
  }
  if (!aeroFlight) {
    return Response.json({ error: "Flight not found" }, { status: 404 });
  }

  const mapped = mapAeroFlightToRow(aeroFlight);

  // Airport coordinates aren't on the /flights response — a one-time /airports/{id} lookup per
  // side. Best-effort: a failed lookup just leaves the columns null, which the map screen
  // already treats as "no marker for this side."
  let originLatitude: number | null = null;
  let originLongitude: number | null = null;
  let destinationLatitude: number | null = null;
  let destinationLongitude: number | null = null;
  try {
    const originCode = mapped.origin_icao ?? mapped.origin_iata;
    if (originCode) {
      const coords = await fetchAirportCoordinates(originCode);
      if (coords) {
        originLatitude = coords.latitude;
        originLongitude = coords.longitude;
      }
    }
  } catch (err) {
    console.error("[add-flight] origin coordinate lookup threw:", (err as Error).message);
  }
  try {
    const destCode = mapped.destination_icao ?? mapped.destination_iata;
    if (destCode) {
      const coords = await fetchAirportCoordinates(destCode);
      if (coords) {
        destinationLatitude = coords.latitude;
        destinationLongitude = coords.longitude;
      }
    }
  } catch (err) {
    console.error("[add-flight] destination coordinate lookup threw:", (err as Error).message);
  }

  const status = deriveFlightStatus(aeroFlight);

  const { data: inserted, error: insertErr } = await serviceClient
    .from("flights")
    .insert({
      ...mapped,
      origin_latitude: originLatitude,
      origin_longitude: originLongitude,
      destination_latitude: destinationLatitude,
      destination_longitude: destinationLongitude,
      status,
      couple_id: couple.id,
      trip_id: input.tripId ?? null,
      traveler_id: travelerId ?? null,
      created_by: user.id,
      last_refreshed_at: new Date().toISOString(),
    })
    .select("id")
    .single();

  if (insertErr || !inserted) {
    console.error("[add-flight] failed to insert flight:", insertErr?.message);
    return Response.json({ error: "Failed to save flight" }, { status: 500 });
  }

  const flightId = inserted.id as string;

  // Baseline event — no prior row to diff against, so this is seeded directly rather than
  // through syncFlight's diff logic.
  const { error: eventErr } = await serviceClient.from("flight_status_events").insert({
    flight_id: flightId,
    type: "scheduled",
    previous_value: null,
    new_value: mapped.scheduled_out,
    source: "poll",
  });
  if (eventErr) {
    console.error("[add-flight] failed to insert baseline event:", eventErr.message);
  }

  // Default notification preferences for both partners. A partner's default state should never
  // be silently suppressed by the flight's creator opting themselves out.
  const partnerIds = [couple.partner_a_id, couple.partner_b_id].filter((id): id is string => Boolean(id));
  const prefRows = partnerIds.map((profileId) => {
    const isCaller = profileId === user.id;
    const optedOut = isCaller && input.notifyMe === false;
    return {
      flight_id: flightId,
      profile_id: profileId,
      gate_terminal_changes: !optedOut,
      delay_or_cancellation: !optedOut,
      departure: !optedOut,
      landing: !optedOut,
      arrival_at_gate: !optedOut,
      baggage_claim_update: !optedOut,
    };
  });
  const { error: prefErr } = await serviceClient.from("flight_notification_preferences").insert(prefRows);
  if (prefErr) {
    console.error("[add-flight] failed to insert notification preferences:", prefErr.message);
  }

  // Best-effort — swallow failures internally, never blocks adding the flight. Requires the
  // account-wide AeroAPI alert webhook endpoint to already be configured (see
  // aeroapi-webhook/index.ts's header comment for the one-time `PUT /alerts/endpoint` step).
  const originCode = mapped.origin_icao ?? mapped.origin_iata;
  const destCode = mapped.destination_icao ?? mapped.destination_iata;
  if (originCode && destCode) {
    await createAlert(aeroFlight.ident, originCode, destCode);
  }

  return Response.json({ flightId });
});

/* To invoke locally:

  1. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  2. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/add-flight' \
    --header 'apiKey: sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH' \
    --header 'Authorization: Bearer <user-access-token>' \
    --data '{"faFlightId":"QFA35-1234567890-airline-0123","notifyMe":true}'

*/
