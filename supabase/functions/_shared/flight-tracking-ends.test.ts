// Every tracked flight stops being polled eventually.
//
// Two rows could be polled forever. A pending row (no fa_flight_id) that never resolved: it has no
// AeroAPI data, so nothing ever moves it to arrived, and each look is a billed /schedules call. And
// a resolved row AeroAPI gave no arrival time for: `reconcileOverdueArrival` measured everything
// from the arrival, and with none it returned without doing anything, every tick.
//
// Against the local stack, like flight-sync-races.test.ts, because the outcome is a column Postgres
// holds. Skipped when the stack isn't up.
//
// Run with: deno test --allow-all --node-modules-dir=none supabase/functions/_shared/flight-tracking-ends.test.ts

import { assertEquals } from "jsr:@std/assert@1";
import { reconcileOverdueArrival, refreshOneFlight } from "./flight-sync.ts";
import {
  aeroRequests,
  installLocalStack,
  onAeroApi,
  removeCouple,
  resetOutbound,
  seedCouple,
  seedFlight,
  serviceClient,
  stackIsUp,
} from "./testing/local-stack.ts";

const up = await stackIsUp();
if (up) await installLocalStack();
const ignore = !up;
if (!up) console.warn("[flight-tracking-ends] local Supabase stack not reachable — skipping");

const MINUTE = 60 * 1000;
const HOUR = 60 * MINUTE;
const iso = (offsetMs: number) => new Date(Date.now() + offsetMs).toISOString();
const quiet = { sanitizeOps: false, sanitizeResources: false };

const schedulesAnswerNothing = (url: URL) =>
  url.pathname.includes("/schedules/") ? Response.json({ scheduled: [] }) : new Response("not found", { status: 404 });

Deno.test({
  name: "a pending flight still unresolved hours after its departure stops being tracked, without another lookup",
  ignore,
  ...quiet,
  fn: async () => {
    resetOutbound();
    onAeroApi(schedulesAnswerNothing);
    const client = serviceClient();
    const couple = await seedCouple(client);
    try {
      const row = await seedFlight(client, couple, {
        fa_flight_id: null,
        scheduled_out: iso(-4 * HOUR),
        scheduled_in: null,
        last_refreshed_at: iso(-20 * MINUTE),
      });
      await refreshOneFlight(client, row, "refresh-due-flights");
      const { data } = await client.from("flights").select("tracking_enabled").eq("id", row.id).single();
      assertEquals(data?.tracking_enabled, false, "still tracked, so still polled");
      assertEquals(aeroRequests.length, 0, "asked /schedules about a flight that has already gone");
    } finally {
      await removeCouple(client, couple);
    }
  },
});

Deno.test({
  name: "a pending flight whose departure passed an hour ago is still given its look",
  ignore,
  ...quiet,
  fn: async () => {
    resetOutbound();
    onAeroApi(schedulesAnswerNothing);
    const client = serviceClient();
    const couple = await seedCouple(client);
    try {
      const row = await seedFlight(client, couple, {
        fa_flight_id: null,
        scheduled_out: iso(-1 * HOUR),
        scheduled_in: null,
        last_refreshed_at: iso(-20 * MINUTE),
      });
      await refreshOneFlight(client, row, "refresh-due-flights");
      const { data } = await client.from("flights").select("tracking_enabled").eq("id", row.id).single();
      assertEquals(data?.tracking_enabled, true);
      assertEquals(aeroRequests.length, 1);
    } finally {
      await removeCouple(client, couple);
    }
  },
});
