// add-flight inserts as service_role, so no policy stands between `tripId` and the row: it saved a
// flight onto whatever trip id it was sent. The table now refuses another couple's trip
// (20261123000200); this is add-flight refusing it first, as a bad request, before it spends
// anything on AeroAPI.
//
// Against the local stack, calling the handler that ships. Skipped when the stack isn't up.
//
// Run with: deno test --allow-all --node-modules-dir=none supabase/functions/add-flight/trip.test.ts

import { assertEquals } from "jsr:@std/assert@1";
import {
  aeroRequests,
  bearerFor,
  installLocalStack,
  loadHandler,
  onAeroApi,
  postJson,
  removeCouple,
  resetOutbound,
  seedCouple,
  serviceClient,
  stackIsUp,
  subscribe,
} from "../_shared/testing/local-stack.ts";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

const up = await stackIsUp();
if (up) await installLocalStack();
if (!up) console.warn("[add-flight trip] local Supabase stack not reachable — skipping");

const HOUR = 60 * 60 * 1000;
const iso = (offsetMs: number) => new Date(Date.now() + offsetMs).toISOString();

async function seedTrip(client: SupabaseClient, coupleId: string): Promise<string> {
  const { data: place, error: placeErr } = await client
    .from("places")
    .insert({ city: `Trip test ${crypto.randomUUID()}`, country: "Nowhere", latitude: 0, longitude: 0 })
    .select("id")
    .single();
  if (placeErr || !place) throw new Error(`place insert failed: ${placeErr?.message}`);
  const { data: trip, error } = await client
    .from("trips")
    .insert({
      couple_id: coupleId,
      origin_id: place.id,
      destination_id: place.id,
      departure_at: iso(48 * HOUR),
      arrival_at: iso(72 * HOUR),
      category: "together",
    })
    .select("id")
    .single();
  if (error || !trip) throw new Error(`trip insert failed: ${error?.message}`);
  return trip.id;
}

function answerAnyFlight() {
  onAeroApi((url) => {
    const match = url.pathname.match(/\/flights\/([^/]+)$/);
    if (!match) return new Response("not found", { status: 404 });
    return Response.json({
      flights: [{
        ident: "QFA1",
        ident_iata: "QF1",
        fa_flight_id: decodeURIComponent(match[1]),
        origin: { code_iata: "SYD" },
        destination: { code_iata: "LHR" },
        scheduled_out: iso(48 * HOUR),
        scheduled_in: iso(70 * HOUR),
      }],
    });
  });
}

Deno.test({
  name: "add-flight refuses a trip that belongs to another couple, before asking AeroAPI",
  ignore: !up,
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    resetOutbound();
    answerAnyFlight();
    const client = serviceClient();
    const ours = await seedCouple(client);
    const theirs = await seedCouple(client);
    try {
      await subscribe(client, ours.partnerA);
      const theirTrip = await seedTrip(client, theirs.coupleId);
      const handler = await loadHandler("add-flight");
      const res = await handler(postJson(
        { faFlightId: `QFA1-${crypto.randomUUID()}`, tripId: theirTrip, notifyMe: true },
        await bearerFor(client, ours.partnerA),
      ));
      await res.body?.cancel();
      assertEquals(res.status, 400);
      assertEquals(aeroRequests.length, 0, "looked the flight up for a trip it could never be saved on");
    } finally {
      await removeCouple(client, ours);
      await removeCouple(client, theirs);
    }
  },
});

Deno.test({
  name: "add-flight links a flight to the couple's own trip",
  ignore: !up,
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    resetOutbound();
    answerAnyFlight();
    const client = serviceClient();
    const ours = await seedCouple(client);
    try {
      await subscribe(client, ours.partnerA);
      const trip = await seedTrip(client, ours.coupleId);
      const handler = await loadHandler("add-flight");
      const res = await handler(postJson(
        // Uppercase, as Swift's UUID.uuidString sends it.
        { faFlightId: `QFA1-${crypto.randomUUID()}`, tripId: trip.toUpperCase(), notifyMe: true },
        await bearerFor(client, ours.partnerA),
      ));
      assertEquals(res.status, 200, await res.clone().text());
      const { flightId } = await res.json();
      const { data } = await client.from("flights").select("trip_id").eq("id", flightId).single();
      assertEquals(data?.trip_id, trip);
    } finally {
      await removeCouple(client, ours);
    }
  },
});
