// The monthly tracking allowance holds when the requests arrive together.
//
// Both ways of spending a slot read the month's usage, decided, and then wrote the ledger row, with
// nothing between the read and the write. Requests sent at once all read the same count: a couple
// on a two-flight allowance who fired five adds, or five "track this flight" taps, at the same
// moment had five flights polled at ~85c each, and nothing about the ledger afterwards said so
// until the invoice did.
//
// Against the local stack, because only Postgres can say whether two transactions overlapped.
// pgTAP runs in one transaction and cannot. Skipped when the stack isn't up.
//
// Run with: deno test --allow-all --node-modules-dir=none supabase/functions/_shared/flight-allowance-races.test.ts

import { assertEquals } from "jsr:@std/assert@1";
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  bearerFor,
  installLocalStack,
  LOCAL_ANON_KEY,
  LOCAL_URL,
  loadHandler,
  onAeroApi,
  postJson,
  removeCouple,
  resetOutbound,
  seedCouple,
  seedFlight,
  serviceClient,
  stackIsUp,
  subscribe,
} from "./testing/local-stack.ts";

const up = await stackIsUp();
if (up) await installLocalStack();
const ignore = !up;
if (!up) console.warn("[flight-allowance-races] local Supabase stack not reachable — skipping");

const HOUR = 60 * 60 * 1000;
const iso = (offsetMs: number) => new Date(Date.now() + offsetMs).toISOString();
const quiet = { sanitizeOps: false, sanitizeResources: false };

// Plus: two tracked flights a month (flight_limit_for_tier).
const PLUS_LIMIT = 2;
const AT_ONCE = 6;

Deno.test({
  name: "enable_flight_tracking fired six times at once on a two-flight allowance tracks two",
  ignore,
  ...quiet,
  fn: async () => {
    resetOutbound();
    const client = serviceClient();
    const couple = await seedCouple(client);
    try {
      await subscribe(client, couple.partnerA);
      const flights = [];
      for (let i = 0; i < AT_ONCE; i++) {
        flights.push(await seedFlight(client, couple, {
          tracking_enabled: false,
          scheduled_out: iso(48 * HOUR),
          scheduled_in: iso(60 * HOUR),
        }));
      }
      const bearer = await bearerFor(client, couple.partnerA);
      const user = createClient(LOCAL_URL, LOCAL_ANON_KEY, {
        auth: { persistSession: false, autoRefreshToken: false },
        global: { headers: { Authorization: bearer } },
      });

      const answers = await Promise.all(flights.map((f) => user.rpc("enable_flight_tracking", { p_flight_id: f.id })));
      const enabled = answers.filter((a) => a.data?.enabled === true).length;

      const { count: ledger } = await client.from("flight_additions").select("id", { count: "exact", head: true })
        .eq("couple_id", couple.coupleId);
      const { count: tracked } = await client.from("flights").select("id", { count: "exact", head: true })
        .eq("couple_id", couple.coupleId).eq("tracking_enabled", true);
      assertEquals(enabled, PLUS_LIMIT, "more flights were enabled than the allowance holds");
      assertEquals(ledger, PLUS_LIMIT);
      assertEquals(tracked, PLUS_LIMIT);
    } finally {
      await removeCouple(client, couple);
    }
  },
});

Deno.test({
  name: "add-flight fired six times at once on a two-flight allowance tracks two",
  ignore,
  ...quiet,
  fn: async () => {
    resetOutbound();
    onAeroApi((url) => {
      const match = url.pathname.match(/\/flights\/([^/]+)$/);
      if (!match) return new Response("not found", { status: 404 });
      const faFlightId = decodeURIComponent(match[1]);
      return Response.json({
        flights: [{
          ident: "QFA1",
          ident_iata: "QF1",
          fa_flight_id: faFlightId,
          origin: { code_iata: "SYD" },
          destination: { code_iata: "LHR" },
          scheduled_out: iso(48 * HOUR),
          scheduled_in: iso(70 * HOUR),
        }],
      });
    });
    const client = serviceClient();
    const couple = await seedCouple(client);
    try {
      await subscribe(client, couple.partnerA);
      const bearer = await bearerFor(client, couple.partnerA);
      const handler = await loadHandler("add-flight");

      const responses = await Promise.all(Array.from({ length: AT_ONCE }, () =>
        handler(postJson({ faFlightId: `QFA1-${crypto.randomUUID()}`, notifyMe: true }, bearer))
      ));
      const bodies = await Promise.all(responses.map((r) => r.json()));
      assertEquals(responses.map((r) => r.status), Array(AT_ONCE).fill(200), JSON.stringify(bodies));

      const { count: ledger } = await client.from("flight_additions").select("id", { count: "exact", head: true })
        .eq("couple_id", couple.coupleId);
      const { count: tracked } = await client.from("flights").select("id", { count: "exact", head: true })
        .eq("couple_id", couple.coupleId).eq("tracking_enabled", true);
      assertEquals(bodies.filter((b) => b.tracking === true).length, PLUS_LIMIT, "more adds were told they're tracked than the allowance holds");
      assertEquals(tracked, PLUS_LIMIT, "more flights are being polled than the allowance holds");
      assertEquals(ledger, PLUS_LIMIT);
      // Every flight still saved: the allowance decides tracking, not whether a flight is kept.
      const { count: saved } = await client.from("flights").select("id", { count: "exact", head: true })
        .eq("couple_id", couple.coupleId);
      assertEquals(saved, AT_ONCE);
    } finally {
      await removeCouple(client, couple);
    }
  },
});
