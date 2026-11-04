// A pending flight is the one place add-flight takes flight fields from the client, so it is the
// one place a client could invent a flight. A pending row with a departure in the past and no
// arrival used to sit on the refresher's one-minute tier forever, making a billed /schedules call
// on every tick for a flight that never existed.
//
// The shape checks run before anything is read, so they need no stack. The confirmation against
// /schedules does, and is skipped when the stack isn't up (see testing/local-stack.ts).
//
// Run with: deno test --allow-all --node-modules-dir=none supabase/functions/add-flight/pending.test.ts

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

const up = await stackIsUp();
if (up) await installLocalStack();
if (!up) console.warn("[add-flight pending] local Supabase stack not reachable — skipping the stack tests");

const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;
const iso = (offsetMs: number) => new Date(Date.now() + offsetMs).toISOString().replace(/\.\d{3}Z$/, "Z");
const quiet = { sanitizeOps: false, sanitizeResources: false };

function pending(overrides: Record<string, unknown> = {}) {
  return {
    flightNumberIata: "QF1",
    identIata: "QF1",
    operatorIata: "QF",
    origin: { iata: "SYD" },
    destination: { iata: "LHR" },
    scheduledOut: iso(10 * DAY),
    scheduledIn: iso(10 * DAY + 19 * HOUR),
    ...overrides,
  };
}

const REFUSED: Array<[string, Record<string, unknown>]> = [
  ["a departure that has already gone", { scheduledOut: iso(-2 * DAY), scheduledIn: null }],
  ["a departure more than a year out", { scheduledOut: iso(400 * DAY), scheduledIn: null }],
  ["a departure that is not a time", { scheduledOut: "tomorrow-ish" }],
  ["an arrival before the departure", { scheduledIn: iso(10 * DAY - HOUR) }],
  ["an arrival three days after the departure", { scheduledIn: iso(13 * DAY) }],
  ["a designator that is not one", { flightNumberIata: "free polling please" }],
];

for (const [what, overrides] of REFUSED) {
  Deno.test({
    name: `add-flight refuses a pending flight with ${what}, before reading anything`,
    ...quiet,
    fn: async () => {
      const handler = await loadHandler("add-flight");
      // No Authorization header: a check that ran after the session lookup would answer 401.
      const res = await handler(postJson({ pending: pending(overrides), notifyMe: true }));
      assertEquals(res.status, 400, `${what} was not refused as a bad request`);
      await res.body?.cancel();
    },
  });
}

Deno.test({
  name: "add-flight refuses a pending flight /schedules has never heard of, and saves nothing",
  ignore: !up,
  ...quiet,
  fn: async () => {
    resetOutbound();
    onAeroApi((url) => {
      if (url.pathname.includes("/schedules/")) return Response.json({ scheduled: [] });
      return new Response("not found", { status: 404 });
    });
    const client = serviceClient();
    const couple = await seedCouple(client);
    try {
      await subscribe(client, couple.partnerA);
      const handler = await loadHandler("add-flight");
      const res = await handler(postJson({ pending: pending(), notifyMe: true }, await bearerFor(client, couple.partnerA)));
      assertEquals(res.status, 404);
      await res.body?.cancel();
      const { count } = await client.from("flights").select("id", { count: "exact", head: true }).eq("couple_id", couple.coupleId);
      assertEquals(count, 0, "a flight nobody can confirm was saved anyway");
      assertEquals(aeroRequests.filter((p) => p.includes("/schedules/")).length, 1, "confirmed with one /schedules call");
    } finally {
      await removeCouple(client, couple);
    }
  },
});

Deno.test({
  name: "add-flight stores the schedule /schedules confirms, not the times the client sent",
  ignore: !up,
  ...quiet,
  fn: async () => {
    resetOutbound();
    const out = iso(10 * DAY);
    const serverIn = iso(10 * DAY + 2 * HOUR);
    onAeroApi((url) => {
      if (url.pathname.includes("/schedules/")) {
        return Response.json({
          scheduled: [{
            ident: "QFA1",
            ident_iata: "QF1",
            ident_icao: "QFA1",
            scheduled_out: out,
            scheduled_in: serverIn,
            origin_iata: "SYD",
            origin_icao: "YSSY",
            destination_iata: "LHR",
            destination_icao: "EGLL",
            fa_flight_id: null,
          }],
        });
      }
      return new Response("not found", { status: 404 });
    });
    const client = serviceClient();
    const couple = await seedCouple(client);
    try {
      await subscribe(client, couple.partnerA);
      const handler = await loadHandler("add-flight");
      const res = await handler(postJson(
        { pending: pending({ scheduledOut: out, scheduledIn: iso(10 * DAY + 19 * HOUR) }), notifyMe: true },
        await bearerFor(client, couple.partnerA),
      ));
      assertEquals(res.status, 200, await res.clone().text());
      const { flightId } = await res.json();
      const { data: row } = await client.from("flights").select("scheduled_out, scheduled_in, fa_flight_id").eq("id", flightId).single();
      assertEquals(new Date(row!.scheduled_out).toISOString(), new Date(out).toISOString());
      assertEquals(new Date(row!.scheduled_in).toISOString(), new Date(serverIn).toISOString(), "the client's arrival time was kept");
      assertEquals(row!.fa_flight_id, null);
    } finally {
      await removeCouple(client, couple);
    }
  },
});
