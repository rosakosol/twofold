// One change to a flight is announced once, however many callers sync it (DB-6).
//
// Three things sync the same flight: the every-minute cron, a person pressing refresh, and the
// AeroAPI webhook. Each reads the row, asks AeroAPI, diffs the answer against what it read, writes,
// then pushes one notification per difference it found. Two of them working from the same read
// both find "it departed", both write, and both push, so each phone got "Flight departed" twice.
// `reconcileOverdueArrival` had the same shape: two callers with the same stale read both forced
// the flight to arrived and both pushed "arrived".
//
// These run against the local stack (see testing/local-stack.ts) because the fix is a guarded
// update, and only Postgres can say whether a guard matched. The second caller is given the same
// stale read as the first, which is exactly what an overlapping caller has.
//
// Run with: deno test --allow-all --node-modules-dir=none supabase/functions/_shared/flight-sync-races.test.ts

import { assertEquals } from "jsr:@std/assert@1";
import type { AeroFlight } from "./aeroapi.ts";
import { reconcileOverdueArrival, syncFlight } from "./flight-sync.ts";
import {
  eventsOf,
  installLocalStack,
  pushesTo,
  registerDevice,
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
if (!up) console.warn("[flight-sync-races] local Supabase stack not reachable — skipping");

const MINUTE = 60 * 1000;
const iso = (offsetMs: number) => new Date(Date.now() + offsetMs).toISOString();

Deno.test({
  name: "two syncs from the same read push 'departed' once per device",
  ignore,
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    resetOutbound();
    const client = serviceClient();
    const couple = await seedCouple(client);
    try {
      const row = await seedFlight(client, couple, {
        scheduled_out: iso(-5 * MINUTE),
        scheduled_in: iso(20 * 60 * MINUTE),
      });
      const traveller = await registerDevice(client, couple.partnerA);
      const partner = await registerDevice(client, couple.partnerB);

      const departed: AeroFlight = {
        ident: "QF1",
        ident_iata: "QF1",
        fa_flight_id: row.fa_flight_id!,
        origin: { code_iata: "SYD" },
        destination: { code_iata: "LHR" },
        scheduled_out: row.scheduled_out,
        scheduled_in: row.scheduled_in,
        actual_out: iso(-1 * MINUTE),
      } as unknown as AeroFlight;

      // Both callers read the row before either wrote: the cron and a refresh press, a second apart.
      await syncFlight(client, row, departed, "poll");
      await syncFlight(client, row, departed, "poll");

      assertEquals(await eventsOf(client, row.id, "departed"), 1, "one departed event recorded");
      assertEquals(pushesTo(traveller).length, 1, "the traveller's phone is told once");
      assertEquals(pushesTo(partner).length, 1, "the partner's phone is told once");
    } finally {
      await removeCouple(client, couple);
    }
  },
});

Deno.test({
  name: "a sync from a stale read still records what it fetched when nobody else wrote",
  ignore,
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    resetOutbound();
    const client = serviceClient();
    const couple = await seedCouple(client);
    try {
      // A flight nobody has refreshed yet (null last_refreshed_at) is the other branch of the guard.
      const row = await seedFlight(client, couple, {
        scheduled_out: iso(3 * 60 * MINUTE),
        scheduled_in: iso(23 * 60 * MINUTE),
        last_refreshed_at: null,
      });
      const fetched = {
        ident: "QF1",
        fa_flight_id: row.fa_flight_id!,
        origin: { code_iata: "SYD" },
        destination: { code_iata: "LHR" },
        scheduled_out: row.scheduled_out,
        scheduled_in: row.scheduled_in,
        gate_origin: "8",
      } as unknown as AeroFlight;

      await syncFlight(client, row, fetched, "poll");

      const { data } = await client.from("flights").select("gate_origin, last_refreshed_at").eq("id", row.id).single();
      assertEquals(data?.gate_origin, "8");
      assertEquals(data?.last_refreshed_at !== null, true, "the refresh is stamped");
      assertEquals(await eventsOf(client, row.id, "gate_change"), 1);
    } finally {
      await removeCouple(client, couple);
    }
  },
});

Deno.test({
  name: "two reconciles of an overdue flight from the same read push 'arrived' once per device",
  ignore,
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    resetOutbound();
    const client = serviceClient();
    const couple = await seedCouple(client);
    try {
      // Best-known arrival 40 minutes ago, provider never confirmed: past the 20-minute backstop.
      const row = await seedFlight(client, couple, {
        status: "in_air",
        scheduled_out: iso(-10 * 60 * MINUTE),
        scheduled_in: iso(-40 * MINUTE),
        actual_out: iso(-10 * 60 * MINUTE),
      });
      const traveller = await registerDevice(client, couple.partnerA);
      const partner = await registerDevice(client, couple.partnerB);

      const now = Date.now();
      await reconcileOverdueArrival(client, row, now);
      await reconcileOverdueArrival(client, row, now);

      assertEquals(await eventsOf(client, row.id, "arrived_at_gate"), 1, "one arrival event recorded");
      assertEquals(pushesTo(traveller).length, 1, "the traveller's phone is told once");
      assertEquals(pushesTo(partner).length, 1, "the partner's phone is told once");
      const { data } = await client.from("flights").select("status").eq("id", row.id).single();
      assertEquals(data?.status, "arrived");
    } finally {
      await removeCouple(client, couple);
    }
  },
});

Deno.test({
  name: "a reconcile does not re-announce a flight a sync already landed",
  ignore,
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    resetOutbound();
    const client = serviceClient();
    const couple = await seedCouple(client);
    try {
      const row = await seedFlight(client, couple, {
        status: "in_air",
        scheduled_out: iso(-10 * 60 * MINUTE),
        scheduled_in: iso(-40 * MINUTE),
        actual_out: iso(-10 * 60 * MINUTE),
      });
      const partner = await registerDevice(client, couple.partnerB);

      // A refresh press confirmed the landing a moment ago; the cron still holds its earlier read.
      await client.from("flights").update({ status: "landed", actual_on: iso(-30 * MINUTE) }).eq("id", row.id);
      await reconcileOverdueArrival(client, row, Date.now());

      assertEquals(await eventsOf(client, row.id, "arrived_at_gate"), 0);
      assertEquals(pushesTo(partner).length, 0);
      const { data } = await client.from("flights").select("status").eq("id", row.id).single();
      assertEquals(data?.status, "landed", "the confirmed status is left alone");
    } finally {
      await removeCouple(client, couple);
    }
  },
});
