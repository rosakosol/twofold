// enforceRateLimit when the limiter itself cannot answer.
//
// It fails open, on purpose, for endpoints where an outage of the feature is worse than a burst.
// The three in front of AeroAPI are not those: each admitted call is a bill, and a limiter that
// stops answering is exactly when a client in a loop would go unnoticed. They ask for fail-closed.

import { assert, assertEquals } from "jsr:@std/assert@1";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { enforceRateLimit } from "./rate-limit.ts";

const LIMIT = { bucket: "test", limit: 1, window: "1 hour" };

function clientAnswering(answer: { data: unknown; error: { message: string } | null }): SupabaseClient {
  return { rpc: () => ({ single: () => Promise.resolve(answer) }) } as unknown as SupabaseClient;
}

const broken = clientAnswering({ data: null, error: { message: "connection refused" } });

Deno.test("a limiter that errors lets the request through by default", async () => {
  assertEquals(await enforceRateLimit(broken, LIMIT), null);
});

Deno.test("a limiter that errors refuses the request when asked to fail closed", async () => {
  const res = await enforceRateLimit(broken, LIMIT, { failClosed: true });
  assert(res, "the request went through with no limiter behind it");
  assertEquals(res.status, 503);
  await res.body?.cancel();
});

Deno.test("fail-closed changes nothing when the limiter answers", async () => {
  assertEquals(await enforceRateLimit(clientAnswering({ data: { allowed: true, retry_after_seconds: 0 }, error: null }), LIMIT, { failClosed: true }), null);
  const res = await enforceRateLimit(clientAnswering({ data: { allowed: false, retry_after_seconds: 30 }, error: null }), LIMIT, { failClosed: true });
  assertEquals(res?.status, 429);
  assertEquals(res?.headers.get("Retry-After"), "30");
  await res?.body?.cancel();
});

for (const name of ["add-flight", "resolve-flight", "refresh-flight"]) {
  Deno.test(`${name} spends AeroAPI money, so its limit fails closed`, async () => {
    const source = await Deno.readTextFile(new URL(`../${name}/index.ts`, import.meta.url));
    assert(/enforceRateLimit\(userClient, RATE_LIMIT, \{ failClosed: true \}\)/.test(source), `${name} fails open`);
  });
}
