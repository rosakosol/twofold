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
import { type FlightRow, loadTrackedFlights } from "./flight-sync.ts";
import {
  maybeSendArrivalReminders,
  maybeSendPreDepartureReminder,
  runDueFlightRefresh,
} from "./flight-refresh-run.ts";
import {
  aeroRequests,
  installLocalStack,
  onAeroApi,
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

// ---------------------------------------------------------------------------
// Scale (DB-4, 7-supabase-NEW-1)
// ---------------------------------------------------------------------------
//
// The run loaded every active couple's id and then every tracked flight with
// `couple_id=in.(…every id…)`. PostgREST caps a response at max_rows (1000 here and on the hosted
// default), with no error: past 1000 tracked flights the rest were silently never refreshed,
// reminded or reconciled. And the id list in the URL grows ~37 bytes a couple until a proxy
// refuses it, which fails the whole run. Every flight was also handled in load order, one at a
// time, with no bound on how long a run takes.

Deno.test({
  name: "every tracked flight is loaded, past PostgREST's 1000-row cap",
  ignore,
  ...quiet,
  fn: async () => {
    const client = serviceClient();
    const couple = await seedCouple(client);
    try {
      const rows = Array.from({ length: 1005 }, (_, i) => ({
        couple_id: couple.coupleId,
        created_by: couple.partnerA,
        flight_number_iata: `QF${i}`,
        status: "scheduled",
        tracking_enabled: true,
        scheduled_out: iso(48 * 60 * MINUTE),
      }));
      const { error } = await client.from("flights").insert(rows);
      if (error) throw new Error(error.message);

      const loaded = await loadTrackedFlights(client);
      const mine = (loaded ?? []).filter((f) => f.couple_id === couple.coupleId);
      assertEquals(mine.length, 1005);
    } finally {
      await removeCouple(client, couple);
    }
  },
});

Deno.test({
  name: "a flight of a couple that has ended is not loaded",
  ignore,
  ...quiet,
  fn: async () => {
    const client = serviceClient();
    const couple = await seedCouple(client);
    try {
      const flight = await seedFlight(client, couple);
      await client.from("couples").update({ status: "dissolved", dissolved_at: new Date().toISOString() }).eq("id", couple.coupleId);
      const loaded = await loadTrackedFlights(client);
      assertEquals((loaded ?? []).some((f) => f.id === flight.id), false);
    } finally {
      await removeCouple(client, couple);
    }
  },
});

/// The fa_flight_id of every flight AeroAPI was asked about, in order.
function askedAbout(): string[] {
  return aeroRequests.map((path) => decodeURIComponent(path.split("/").pop()!));
}

Deno.test({
  name: "when a run can't reach every due flight, the latest against its own cadence goes first",
  ignore,
  ...quiet,
  fn: async () => {
    resetOutbound();
    const client = serviceClient();
    const couple = await seedCouple(client);
    try {
      // Next month, last looked at seven hours ago: one hour past its six-hour cadence.
      const farOut = await seedFlight(client, couple, {
        scheduled_out: iso(30 * 24 * 60 * MINUTE),
        scheduled_in: iso(30 * 24 * 60 * MINUTE + 10 * 60 * MINUTE),
        last_refreshed_at: iso(-7 * 60 * MINUTE),
        weather_updated_at: iso(-60 * MINUTE),
      });
      // Departs in five minutes, last looked at three minutes ago: three times its one-minute cadence.
      const boarding = await seedFlight(client, couple, {
        scheduled_out: iso(5 * MINUTE),
        scheduled_in: iso(10 * 60 * MINUTE),
        last_refreshed_at: iso(-3 * MINUTE),
        weather_updated_at: iso(-60 * MINUTE),
      });

      await runDueFlightRefresh(client, {
        loadTrackedFlights: () => Promise.resolve([farOut, boarding]),
        syncLivePositions: () => Promise.resolve(),
        maxRefreshesPerRun: 1,
      });

      assertEquals(askedAbout(), [boarding.fa_flight_id], "only the flight about to leave");
    } finally {
      await removeCouple(client, couple);
    }
  },
});

Deno.test({
  name: "a run stops asking AeroAPI once it is rate limited",
  ignore,
  ...quiet,
  fn: async () => {
    resetOutbound();
    onAeroApi(() => new Response("Too many requests", { status: 429 }));
    const client = serviceClient();
    const couple = await seedCouple(client);
    try {
      const flights: FlightRow[] = [];
      for (let i = 0; i < 3; i++) {
        flights.push(await seedFlight(client, couple, {
          scheduled_out: iso(60 * MINUTE),
          scheduled_in: iso(10 * 60 * MINUTE),
          last_refreshed_at: null,
          // Weather was fetched an hour ago, so only the flight lookups reach AeroAPI.
          weather_updated_at: iso(-60 * MINUTE),
        }));
      }

      const result = await runDueFlightRefresh(client, {
        loadTrackedFlights: () => Promise.resolve(flights),
        syncLivePositions: () => Promise.resolve(),
        interCallDelayMs: 0,
      });

      // The first lookup and its one retry; nothing after.
      assertEquals(aeroRequests.length, 2, aeroRequests.join(", "));
      assertEquals(result.ok && result.deferred, 2);
    } finally {
      resetOutbound();
      await removeCouple(client, couple);
    }
  },
});

Deno.test({
  name: "a run stops starting refreshes when its time is up",
  ignore,
  ...quiet,
  fn: async () => {
    resetOutbound();
    const client = serviceClient();
    const couple = await seedCouple(client);
    try {
      const flights: FlightRow[] = [];
      for (let i = 0; i < 3; i++) {
        flights.push(await seedFlight(client, couple, {
          scheduled_out: iso(60 * MINUTE),
          scheduled_in: iso(10 * 60 * MINUTE),
          last_refreshed_at: null,
          weather_updated_at: iso(-60 * MINUTE),
        }));
      }

      // A clock that moves a minute every time it is read: the budget is gone after the first.
      let clock = Date.now();
      const result = await runDueFlightRefresh(client, {
        loadTrackedFlights: () => Promise.resolve(flights),
        syncLivePositions: () => Promise.resolve(),
        interCallDelayMs: 0,
        clock: () => (clock += MINUTE),
      });

      assertEquals(aeroRequests.length, 1, aeroRequests.join(", "));
      assertEquals(result.ok && result.deferred, 2);
    } finally {
      await removeCouple(client, couple);
    }
  },
});
