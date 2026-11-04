// resolve-flight spends AeroAPI money on every search, and add-flight — the end of the same flow —
// refuses a couple without a subscription. Searching was left open, so a lapsed couple could keep
// searching all day and only meet the refusal at the final tap. Both now refuse the same way, with
// the same body, so the app reads one code for one meaning.
//
// Against the local stack, calling the handler that ships. Skipped when the stack isn't up.
//
// Run with: deno test --allow-all --node-modules-dir=none supabase/functions/resolve-flight/subscription.test.ts

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
const ignore = !up;
if (!up) console.warn("[resolve-flight subscription] local Supabase stack not reachable — skipping");

const quiet = { sanitizeOps: false, sanitizeResources: false };
const search = () => ({ mode: "number", flightNumber: "QF1", date: new Date().toISOString().slice(0, 10) });

Deno.test({
  name: "resolve-flight refuses a couple with no subscription before searching, as add-flight does",
  ignore,
  ...quiet,
  fn: async () => {
    resetOutbound();
    onAeroApi(() => Response.json({ flights: [], scheduled: [] }));
    const client = serviceClient();
    const couple = await seedCouple(client);
    try {
      const handler = await loadHandler("resolve-flight");
      const res = await handler(postJson(search(), await bearerFor(client, couple.partnerA)));
      assertEquals(res.status, 403);
      const body = await res.json();
      assertEquals(body.code, "subscription_required");
      assertEquals(typeof body.error, "string");
      assertEquals(aeroRequests.length, 0, "searched AeroAPI for a couple who can't add what it finds");
    } finally {
      await removeCouple(client, couple);
    }
  },
});

Deno.test({
  name: "resolve-flight searches for a subscribed couple",
  ignore,
  ...quiet,
  fn: async () => {
    resetOutbound();
    onAeroApi(() => Response.json({ flights: [], scheduled: [] }));
    const client = serviceClient();
    const couple = await seedCouple(client);
    try {
      // Either partner's subscription covers the couple.
      await subscribe(client, couple.partnerB);
      const handler = await loadHandler("resolve-flight");
      const res = await handler(postJson(search(), await bearerFor(client, couple.partnerA)));
      await res.body?.cancel();
      assertEquals(res.status, 200);
    } finally {
      await removeCouple(client, couple);
    }
  },
});
