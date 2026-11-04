// refresh-flight is a person asking for an AeroAPI lookup now, so what it may spend has to be
// bounded by the server, not by how often the app happens to ask.
//
// Three ways it wasn't: no per-account limit at all; a 60-second dedup that read last_refreshed_at
// and only then called AeroAPI, so calls arriving together all passed it; and a lookup AeroAPI
// answered with no flight left last_refreshed_at where it was, so the dedup never engaged for that
// flight and neither did the cron's cadence.
//
// Against the local stack, calling the handler that ships (see testing/local-stack.ts). Skipped
// when the stack isn't up.
//
// Run with: deno test --allow-all --node-modules-dir=none supabase/functions/refresh-flight/refresh.test.ts

import { assert, assertEquals } from "jsr:@std/assert@1";
import { refreshOneFlight } from "../_shared/flight-sync.ts";
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
  seedFlight,
  serviceClient,
  stackIsUp,
} from "../_shared/testing/local-stack.ts";

const up = await stackIsUp();
if (up) await installLocalStack();
const ignore = !up;
if (!up) console.warn("[refresh-flight] local Supabase stack not reachable — skipping");

const MINUTE = 60 * 1000;
const HOUR = 60 * MINUTE;
const iso = (offsetMs: number) => new Date(Date.now() + offsetMs).toISOString();
const quiet = { sanitizeOps: false, sanitizeResources: false };

const flightLookups = () => aeroRequests.filter((p) => /\/flights\/[^/]+$/.test(p)).length;

Deno.test({
  name: "five refreshes of one flight at once make one AeroAPI lookup",
  ignore,
  ...quiet,
  fn: async () => {
    resetOutbound();
    onAeroApi((url) => url.pathname.includes("/flights/") ? Response.json({ flights: [] }) : new Response(null, { status: 404 }));
    const client = serviceClient();
    const couple = await seedCouple(client);
    try {
      const flight = await seedFlight(client, couple, {
        scheduled_out: iso(5 * HOUR),
        scheduled_in: iso(15 * HOUR),
        last_refreshed_at: iso(-30 * MINUTE),
      });
      const handler = await loadHandler("refresh-flight");
      const bearer = await bearerFor(client, couple.partnerA);
      const responses = await Promise.all(Array.from({ length: 5 }, () => handler(postJson({ flightId: flight.id }, bearer))));
      for (const r of responses) await r.body?.cancel();
      assertEquals(responses.map((r) => r.status), [200, 200, 200, 200, 200]);
      assertEquals(flightLookups(), 1, "every caller that read a stale stamp made its own lookup");
    } finally {
      await removeCouple(client, couple);
    }
  },
});

Deno.test({
  name: "an account past its refresh limit is refused before AeroAPI is asked",
  ignore,
  ...quiet,
  fn: async () => {
    resetOutbound();
    onAeroApi(() => Response.json({ flights: [] }));
    const client = serviceClient();
    const couple = await seedCouple(client);
    try {
      const flight = await seedFlight(client, couple, { last_refreshed_at: iso(-30 * MINUTE) });
      // A full hour's budget already spent, as if by an app (or a script) asking in a loop.
      const spent = Array.from({ length: 60 }, () => ({ user_id: couple.partnerA, bucket: "refresh-flight" }));
      const { error } = await client.from("rate_limit_events").insert(spent);
      if (error) throw new Error(error.message);

      const handler = await loadHandler("refresh-flight");
      const res = await handler(postJson({ flightId: flight.id }, await bearerFor(client, couple.partnerA)));
      await res.body?.cancel();
      assertEquals(res.status, 429);
      assert(res.headers.get("Retry-After"), "no Retry-After on the refusal");
      assertEquals(flightLookups(), 0);
    } finally {
      await client.from("rate_limit_events").delete().eq("user_id", couple.partnerA);
      await removeCouple(client, couple);
    }
  },
});

Deno.test({
  name: "a lookup AeroAPI answers with no flight still counts as a refresh",
  ignore,
  ...quiet,
  fn: async () => {
    resetOutbound();
    onAeroApi(() => Response.json({ flights: [] }));
    const client = serviceClient();
    const couple = await seedCouple(client);
    try {
      const flight = await seedFlight(client, couple, { last_refreshed_at: iso(-30 * MINUTE) });
      const before = Date.now();
      await refreshOneFlight(client, flight, "refresh-due-flights");
      const { data } = await client.from("flights").select("last_refreshed_at").eq("id", flight.id).single();
      assert(
        Date.parse(data!.last_refreshed_at) >= before - 1000,
        "last_refreshed_at left behind, so the flight stays due on every tick",
      );
    } finally {
      await removeCouple(client, couple);
    }
  },
});
