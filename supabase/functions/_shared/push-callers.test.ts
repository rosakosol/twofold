// What the push fan-outs report, end to end through the handlers that ship.
//
// sendAPNs reports what Apple said about each push, and every caller dropped it. notify-game-turn
// went further and answered `sent: tokens.length`, the number of phones it *tried*, so a turn
// pushed to a retired phone came back as a success. These load the real index.ts (with
// `Deno.serve` captured instead of listening) against the local stack, with Apple's answers
// chosen per token.
//
// Run with: deno test --allow-all --node-modules-dir=none supabase/functions/_shared/push-callers.test.ts

import { assert, assertEquals } from "jsr:@std/assert@1";
import { APNS_RETRY } from "./apns.ts";
import {
  installLocalStack,
  LOCAL_SERVICE_KEY,
  onApns,
  registerDevice,
  removeCouple,
  resetOutbound,
  seedCouple,
  serviceClient,
  stackIsUp,
} from "./testing/local-stack.ts";

const up = await stackIsUp();
if (up) await installLocalStack();
const ignore = !up;
if (!up) console.warn("[push-callers] local Supabase stack not reachable — skipping");

const quiet = { sanitizeOps: false, sanitizeResources: false };

type Handler = (req: Request) => Response | Promise<Response>;

async function load(name: string): Promise<Handler> {
  // deno-lint-ignore no-explicit-any
  const d = Deno as any;
  const realServe = d.serve;
  let captured: Handler | undefined;
  d.serve = (handler: Handler) => {
    captured = handler;
    return { finished: Promise.resolve(), shutdown: () => Promise.resolve() };
  };
  try {
    await import(`../${name}/index.ts`);
  } finally {
    d.serve = realServe;
  }
  assert(captured, `${name} did not register a handler`);
  return captured;
}

Deno.test({
  name: "notify-game-turn reports what was delivered, not how many phones it tried",
  ignore,
  ...quiet,
  fn: async () => {
    resetOutbound();
    APNS_RETRY.delayMs = 0;
    const client = serviceClient();
    const couple = await seedCouple(client);
    try {
      const live = await registerDevice(client, couple.partnerB);
      const retired = await registerDevice(client, couple.partnerB);
      const down = await registerDevice(client, couple.partnerB);
      onApns((token) =>
        token === retired
          ? new Response(JSON.stringify({ reason: "Unregistered" }), { status: 410 })
          : token === down
          ? new Response(null, { status: 503 })
          : new Response(null, { status: 200 })
      );

      const handler = await load("notify-game-turn");
      const res = await handler(
        new Request("http://localhost/", {
          method: "POST",
          headers: { Authorization: `Bearer ${LOCAL_SERVICE_KEY}`, "Content-Type": "application/json" },
          body: JSON.stringify({
            actorId: couple.partnerA,
            actorName: "Ada",
            recipientId: couple.partnerB,
            sessionId: crypto.randomUUID(),
            gameType: "connect_four",
          }),
        }),
      );
      const body = await res.json();

      assertEquals(body.sent, 1, JSON.stringify(body));
      assertEquals(body.failed, 2, JSON.stringify(body));
      assertEquals(body.retired, 1, JSON.stringify(body));

      const { data: left } = await client.from("device_push_tokens").select("apns_token").eq("profile_id", couple.partnerB);
      assertEquals(
        (left ?? []).map((r) => r.apns_token).sort(),
        [live, down].sort(),
        "the retired phone is forgotten; the one Apple was down for is kept",
      );
    } finally {
      APNS_RETRY.delayMs = 1000;
      await removeCouple(client, couple);
    }
  },
});
