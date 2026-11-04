// aeroapi-webhook is public: its only gate is the `token` query parameter. It was compared with
// `!==`, which returns at the first differing character and so answers faster the more of a guess
// is wrong — the shape a timing attack reads. It now goes through `timingSafeEqual`, the comparison
// the service-role check uses (_shared/auth.ts).
//
// Run with: deno test --allow-all --node-modules-dir=none supabase/functions/aeroapi-webhook/token.test.ts

import { assert, assertEquals } from "jsr:@std/assert@1";
import { loadHandler } from "../_shared/testing/local-stack.ts";

const TOKEN = "webhook-token-for-tests";
Deno.env.set("AEROAPI_WEBHOOK_TOKEN", TOKEN);

const diag = (token?: string) =>
  new Request(`http://localhost/?diag=apns${token === undefined ? "" : `&token=${encodeURIComponent(token)}`}`);

Deno.test("the webhook token is compared in constant time", async () => {
  const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  assert(!/token\s*!==/.test(source), "still compares the token with !==");
  assert(/timingSafeEqual\(/.test(source), "does not use timingSafeEqual");
});

Deno.test("a wrong, short, long or missing token is refused", async () => {
  const handler = await loadHandler("aeroapi-webhook");
  for (const token of [undefined, "", "w", `${TOKEN}x`, TOKEN.slice(0, -1), "undefined"]) {
    const res = await handler(diag(token));
    await res.body?.cancel();
    assertEquals(res.status, 401, `token=${token} was let in`);
  }
});

Deno.test("the right token is let in", async () => {
  const handler = await loadHandler("aeroapi-webhook");
  const res = await handler(diag(TOKEN));
  await res.body?.cancel();
  assertEquals(res.status, 200);
});

Deno.test("with the token unset, nobody is let in", async () => {
  const handler = await loadHandler("aeroapi-webhook");
  Deno.env.delete("AEROAPI_WEBHOOK_TOKEN");
  try {
    for (const token of ["", "undefined"]) {
      const res = await handler(diag(token));
      await res.body?.cancel();
      assertEquals(res.status, 401, `token=${token} was let in with no token configured`);
    }
  } finally {
    Deno.env.set("AEROAPI_WEBHOOK_TOKEN", TOKEN);
  }
});
