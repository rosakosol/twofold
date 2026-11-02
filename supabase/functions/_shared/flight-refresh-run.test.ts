// The flight refresh cron: one run at a time, and each reminder sent once (DB-5).
//
// pg_cron fires the run every minute and does not wait for the last one. A run that took longer
// than a minute overlapped the next, and both worked through the same flights from the same reads:
// two AeroAPI calls per flight, and both passing "reminder not sent yet" and sending it. The run
// now takes a lease first (20261118000100), and each reminder is claimed in the database before it
// is sent, so a second sender holding the same read finds it already claimed.
//
// Against the local stack (see testing/local-stack.ts). The runs are handed only the flights each
// test seeded, so other local data is never touched.
//
// Run with: deno test --allow-all --node-modules-dir=none supabase/functions/_shared/flight-refresh-run.test.ts

import { assertEquals } from "jsr:@std/assert@1";
import type { FlightRow } from "./flight-sync.ts";
import {
  maybeSendArrivalReminders,
  maybeSendPreDepartureReminder,
  runDueFlightRefresh,
} from "./flight-refresh-run.ts";
import {
  aeroRequests,
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
if (!up) console.warn("[flight-refresh-run] local Supabase stack not reachable — skipping");

const MINUTE = 60 * 1000;
const iso = (offsetMs: number) => new Date(Date.now() + offsetMs).toISOString();
const quiet = { sanitizeOps: false, sanitizeResources: false };

Deno.test({
  name: "a run while another run holds the lease touches nothing",
  ignore,
  ...quiet,
  fn: async () => {
    resetOutbound();
    const client = serviceClient();
    const couple = await seedCouple(client);
    const { data: holder } = await client.rpc("claim_cron_lease", { p_job: "refresh-due-flights", p_ttl_seconds: 60 });
    try {
      // Due now: never refreshed.
      const flight = await seedFlight(client, couple, {
        scheduled_out: iso(60 * MINUTE),
        scheduled_in: iso(20 * 60 * MINUTE),
        last_refreshed_at: null,
      });
      let loads = 0;
      const result = await runDueFlightRefresh(client, {
        loadTrackedFlights: () => {
          loads++;
          return Promise.resolve([flight]);
        },
        syncLivePositions: () => Promise.resolve(),
      });

      assertEquals(loads, 0, "the second run never loads a flight");
      assertEquals(aeroRequests.length, 0, "nor asks AeroAPI about one");
      assertEquals(result.ok && result.alreadyRunning, true);
    } finally {
      if (holder) await client.rpc("release_cron_lease", { p_job: "refresh-due-flights", p_holder: holder });
      await removeCouple(client, couple);
    }
  },
});

Deno.test({
  name: "a run gives the lease back when it finishes",
  ignore,
  ...quiet,
  fn: async () => {
    resetOutbound();
    const client = serviceClient();
    const first = await runDueFlightRefresh(client, {
      loadTrackedFlights: () => Promise.resolve([]),
      syncLivePositions: () => Promise.resolve(),
    });
    assertEquals(first.ok && !first.alreadyRunning, true);
    const { data: holder } = await client.rpc("claim_cron_lease", { p_job: "refresh-due-flights", p_ttl_seconds: 60 });
    assertEquals(holder !== null, true, "the next run can take it");
    await client.rpc("release_cron_lease", { p_job: "refresh-due-flights", p_holder: holder });
  },
});

Deno.test({
  name: "two senders holding the same read send the pre-departure reminder once",
  ignore,
  ...quiet,
  fn: async () => {
    resetOutbound();
    const client = serviceClient();
    const couple = await seedCouple(client);
    try {
      // Partner A is flying in eight minutes; partner B is the one told to wish them well.
      const flight = await seedFlight(client, couple, {
        scheduled_out: iso(8 * MINUTE),
        scheduled_in: iso(10 * 60 * MINUTE),
      });
      const partner = await registerDevice(client, couple.partnerB);

      const now = Date.now();
      await maybeSendPreDepartureReminder(client, flight, now);
      await maybeSendPreDepartureReminder(client, flight, now);

      assertEquals(pushesTo(partner).length, 1);
      const { data } = await client.from("flights").select("pre_departure_notified").eq("id", flight.id).single();
      assertEquals(data?.pre_departure_notified, true);
    } finally {
      await removeCouple(client, couple);
    }
  },
});

Deno.test({
  name: "two senders holding the same read send the 1-hour arrival reminder once per phone",
  ignore,
  ...quiet,
  fn: async () => {
    resetOutbound();
    const client = serviceClient();
    const couple = await seedCouple(client);
    try {
      // Lands in 45 minutes: inside the 1-hour window, not yet the 30-minute one.
      const flight = await seedFlight(client, couple, {
        status: "in_air",
        scheduled_out: iso(-5 * 60 * MINUTE),
        scheduled_in: iso(45 * MINUTE),
        actual_out: iso(-5 * 60 * MINUTE),
      });
      const traveller = await registerDevice(client, couple.partnerA);
      const partner = await registerDevice(client, couple.partnerB);

      const now = Date.now();
      await maybeSendArrivalReminders(client, flight, now);
      await maybeSendArrivalReminders(client, flight, now);

      assertEquals(pushesTo(traveller).length, 1, "the traveller's phone is told once");
      assertEquals(pushesTo(partner).length, 1, "the partner's phone is told once");
      const { data } = await client.from("flights").select("arrival_1h_notified").eq("id", flight.id).single();
      assertEquals(data?.arrival_1h_notified, true);
    } finally {
      await removeCouple(client, couple);
    }
  },
});

Deno.test({
  name: "a moved arrival re-arms its reminder once, not once per sender",
  ignore,
  ...quiet,
  fn: async () => {
    resetOutbound();
    const client = serviceClient();
    const couple = await seedCouple(client);
    try {
      // The 1-hour reminder went out for an arrival ten minutes from now; it now lands in 50.
      const flight: FlightRow = await seedFlight(client, couple, {
        status: "in_air",
        scheduled_out: iso(-5 * 60 * MINUTE),
        scheduled_in: iso(50 * MINUTE),
        actual_out: iso(-5 * 60 * MINUTE),
        arrival_1h_notified: true,
        arrival_1h_notified_for: iso(10 * MINUTE),
      });
      const partner = await registerDevice(client, couple.partnerB);

      const now = Date.now();
      await maybeSendArrivalReminders(client, flight, now);
      await maybeSendArrivalReminders(client, flight, now);

      assertEquals(pushesTo(partner).length, 1, "re-sent once for the new time");
    } finally {
      await removeCouple(client, couple);
    }
  },
});
