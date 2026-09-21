// The preflight is the one response nobody sees fail.
//
// A function that gets this wrong logs nothing, returns nothing the caller can read, and reports
// itself as healthy — the browser discards the answer before any of our code is involved. So the
// behaviour is pinned here rather than discovered from a console that says "couldn't reach the
// server" and means "your function said 405 to a question it was supposed to say yes to".

import { assertEquals, assertExists, assertFalse } from "jsr:@std/assert@1";
import { corsHeadersFor, serveWithCors } from "./cors.ts";

const CONSOLE = "https://twofoldapp.com.au";

function get(response: Response, header: string): string | null {
  return response.headers.get(header);
}

Deno.test("a preflight is answered without running the handler", async () => {
  let ran = false;
  const handler = serveWithCors(() => {
    ran = true;
    return new Response("should not happen", { status: 500 });
  });

  const response = await handler(
    new Request("https://example.test/fn", { method: "OPTIONS", headers: { Origin: CONSOLE } }),
  );

  assertEquals(response.status, 204);
  assertEquals(get(response, "Access-Control-Allow-Origin"), CONSOLE);
  assertFalse(ran, "the handler must not see a preflight");
});

Deno.test("the real response carries the headers too", async () => {
  // Answering only the preflight moves the failure one step later: the browser makes the call and
  // then throws the answer away.
  const handler = serveWithCors(() => Response.json({ ok: true }));

  const response = await handler(
    new Request("https://example.test/fn", { method: "POST", headers: { Origin: CONSOLE } }),
  );

  assertEquals(response.status, 200);
  assertEquals(get(response, "Access-Control-Allow-Origin"), CONSOLE);
  assertEquals(await response.json(), { ok: true });
});

Deno.test("an error response carries them as well", async () => {
  // Without this the browser blocks the 403 and the console shows a network failure instead of
  // "Not authorised" — which is the whole reason the message was unreadable in the first place.
  const handler = serveWithCors(() => Response.json({ error: "Not authorised" }, { status: 403 }));

  const response = await handler(
    new Request("https://example.test/fn", { method: "POST", headers: { Origin: CONSOLE } }),
  );

  assertEquals(response.status, 403);
  assertEquals(get(response, "Access-Control-Allow-Origin"), CONSOLE);
});

Deno.test("an origin we do not know gets no permission", async () => {
  const headers = corsHeadersFor("https://not-ours.example");
  assertEquals(headers["Access-Control-Allow-Origin"], undefined);
  // Still varies on Origin: a cache must not hand this answer to a caller we DO allow.
  assertEquals(headers["Vary"], "Origin");
});

Deno.test("a native caller sends no Origin and is unaffected", async () => {
  let ran = false;
  const handler = serveWithCors(() => {
    ran = true;
    return Response.json({ ok: true });
  });

  const response = await handler(new Request("https://example.test/fn", { method: "POST" }));

  assertEquals(ran, true);
  assertEquals(response.status, 200);
  assertEquals(get(response, "Access-Control-Allow-Origin"), null);
});

Deno.test("every header supabase-js sends is allowed", () => {
  const allowed = corsHeadersFor(CONSOLE)["Access-Control-Allow-Headers"]
    .split(",")
    .map((value) => value.trim().toLowerCase());

  // One missing entry fails the preflight exactly as completely as sending no CORS headers at all.
  for (const header of ["authorization", "apikey", "content-type", "x-client-info"]) {
    assertEquals(allowed.includes(header), true, `${header} must be allowed`);
  }
  assertExists(corsHeadersFor(CONSOLE)["Access-Control-Allow-Methods"]);
});

Deno.test("extra origins can be configured, for preview deployments", () => {
  Deno.env.set("CONSOLE_ALLOWED_ORIGINS", "https://preview-abc.vercel.app, https://other.test");
  try {
    assertEquals(
      corsHeadersFor("https://preview-abc.vercel.app")["Access-Control-Allow-Origin"],
      "https://preview-abc.vercel.app",
    );
    assertEquals(corsHeadersFor(CONSOLE)["Access-Control-Allow-Origin"], CONSOLE);
  } finally {
    Deno.env.delete("CONSOLE_ALLOWED_ORIGINS");
  }
});
