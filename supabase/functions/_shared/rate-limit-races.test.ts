// consume_rate_limit admits no more than its limit when the calls arrive together.
//
// It counted the caller's rows in the window and inserted one if there was room, with nothing
// between the two, so calls sent at once all counted the same rows and all got in. Every limit in
// the project is this function, and the ones in front of AeroAPI are the expensive ones.
//
// Against the local stack, like flight-allowance-races.test.ts. Skipped when the stack isn't up.
//
// Run with: deno test --allow-all --node-modules-dir=none supabase/functions/_shared/rate-limit-races.test.ts

import { assertEquals } from "jsr:@std/assert@1";
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  bearerFor,
  installLocalStack,
  LOCAL_ANON_KEY,
  LOCAL_URL,
  removeCouple,
  seedCouple,
  serviceClient,
  stackIsUp,
} from "./testing/local-stack.ts";

const up = await stackIsUp();
if (up) await installLocalStack();
if (!up) console.warn("[rate-limit-races] local Supabase stack not reachable — skipping");

Deno.test({
  name: "ten calls at once against a limit of three admit three",
  ignore: !up,
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const client = serviceClient();
    const couple = await seedCouple(client);
    try {
      const user = createClient(LOCAL_URL, LOCAL_ANON_KEY, {
        auth: { persistSession: false, autoRefreshToken: false },
        global: { headers: { Authorization: await bearerFor(client, couple.partnerA) } },
      });
      const bucket = `race-${crypto.randomUUID().slice(0, 8)}`;
      const answers = await Promise.all(Array.from({ length: 10 }, () =>
        user.rpc("consume_rate_limit", { p_bucket: bucket, p_limit: 3, p_window: "1 hour" }).single()
      ));
      const allowed = answers.filter((a) => (a.data as { allowed: boolean } | null)?.allowed === true).length;
      assertEquals(answers.filter((a) => a.error).length, 0, JSON.stringify(answers.map((a) => a.error)));
      assertEquals(allowed, 3, "more calls were admitted than the limit");
    } finally {
      await removeCouple(client, couple);
    }
  },
});
