// Two properties, and the first one is the only reason this module is safe to put inside
// `aeroRequest` at all.
//
// `recordApiCall` sits in the hot path of the cron job that keeps every tracked flight up to date.
// If it can throw, then a bad afternoon at the metering table becomes a bad afternoon for flight
// tracking — notifications stop, Live Activities go stale, and the cause is bookkeeping. So it must
// swallow everything: a rejected insert, an error in the response, a client that throws
// synchronously, a client that does not exist at all.
//
// The second is that `usageArgs` names the SQL function's parameters exactly. A typo there does not
// fail loudly; it writes a row with a null where attribution should be, which reads in the console
// as an unattributed call path rather than as a bug, and would send someone looking in the wrong
// place for it.

import { assertEquals } from "jsr:@std/assert@1";
import { recordApiCall, usageArgs } from "./api-usage.ts";

const OUTCOME = {
  provider: "aeroapi",
  endpoint: "flights/{id}",
  status: 200,
  wasRetry: false,
  durationMs: 42,
};

// deno-lint-ignore no-explicit-any
function fakeClient(rpc: (name: string, args: unknown) => any): any {
  return { rpc };
}

Deno.test("a rejected insert does not reach the caller", async () => {
  const client = fakeClient(() => Promise.reject(new Error("connection refused")));
  await recordApiCall(OUTCOME, { calledBy: "refresh-due-flights" }, client);
});

Deno.test("an error in the response does not reach the caller", async () => {
  const client = fakeClient(() => Promise.resolve({ error: { message: "permission denied" } }));
  await recordApiCall(OUTCOME, { calledBy: "refresh-due-flights" }, client);
});

Deno.test("a client that throws synchronously does not reach the caller", async () => {
  const client = fakeClient(() => {
    throw new Error("exploded before returning a promise");
  });
  await recordApiCall(OUTCOME, { calledBy: "refresh-due-flights" }, client);
});

Deno.test("no client at all is a no-op, not a failure", async () => {
  // This is the local-development and test case: no service role key in the environment. Metering
  // is not available, and nothing that depends on it should notice.
  await recordApiCall(OUTCOME, { calledBy: "refresh-due-flights" }, null);
});

Deno.test("the recorded row carries the attribution the caller supplied", () => {
  const args = usageArgs(OUTCOME, {
    calledBy: "refresh-due-flights",
    faFlightId: "QF9-1762000000-schedule-0000",
    flightId: "11111111-2222-3333-4444-555555555555",
    coupleId: "66666666-7777-8888-9999-000000000000",
  });

  assertEquals(args, {
    p_provider: "aeroapi",
    p_endpoint: "flights/{id}",
    p_called_by: "refresh-due-flights",
    p_status: 200,
    p_was_retry: false,
    p_duration_ms: 42,
    p_fa_flight_id: "QF9-1762000000-schedule-0000",
    p_flight_id: "11111111-2222-3333-4444-555555555555",
    p_couple_id: "66666666-7777-8888-9999-000000000000",
    p_served_flight_count: 1,
  });
});

Deno.test("a call with no context is recorded as unattributed rather than dropped", () => {
  // An unmetered call would be invisible; an unattributed one is visible and points at the call
  // path that still needs threading. The row is always written.
  const args = usageArgs(OUTCOME);
  assertEquals(args.p_called_by, "unattributed");
  assertEquals(args.p_fa_flight_id, null);
  assertEquals(args.p_served_flight_count, 1);
});

Deno.test("a failed request is recorded with a null status, not skipped", () => {
  const args = usageArgs({ ...OUTCOME, status: null }, { calledBy: "refresh-due-flights" });
  assertEquals(args.p_status, null);
});

Deno.test("served_flight_count never drops below one", () => {
  // Guards the dedupe work that has not happened yet: when one call starts serving N rows, a
  // miscount of 0 would make that call look free. The SQL applies the same floor.
  for (const count of [0, -5]) {
    const args = usageArgs(OUTCOME, { calledBy: "x", servedFlightCount: count });
    assertEquals(args.p_served_flight_count, 1, `servedFlightCount ${count}`);
  }
  assertEquals(
    usageArgs(OUTCOME, { calledBy: "x", servedFlightCount: 4 }).p_served_flight_count,
    4,
  );
});
