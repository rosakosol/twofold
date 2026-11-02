import { assert, assertEquals } from "jsr:@std/assert@1";
import { isServiceRoleRequest, timingSafeEqual, userSession } from "./auth.ts";

const KEY = "service-role-key-for-tests";

function withAuth(value: string | null): Request {
  const headers = new Headers();
  if (value !== null) headers.set("Authorization", value);
  return new Request("http://localhost/functions/v1/purge-r2-objects", { method: "POST", headers });
}

Deno.test("timingSafeEqual: equal strings match, anything else does not", async () => {
  assert(await timingSafeEqual("Bearer abc", "Bearer abc"));
  assert(await timingSafeEqual("", ""));
  assertEquals(await timingSafeEqual("Bearer abc", "Bearer abd"), false);
  // Unequal lengths, either way round, including a prefix of the secret.
  assertEquals(await timingSafeEqual("Bearer ab", "Bearer abc"), false);
  assertEquals(await timingSafeEqual("Bearer abcd", "Bearer abc"), false);
  assertEquals(await timingSafeEqual("", "Bearer abc"), false);
  // Multi-byte characters compare by their bytes, not by UTF-16 units.
  assertEquals(await timingSafeEqual("é", "é"), false);
});

Deno.test("timingSafeEqual does not return early: it always compares whole SHA-256 digests", async () => {
  const source = await Deno.readTextFile(new URL("./auth.ts", import.meta.url));
  const body = source.slice(source.indexOf("export async function timingSafeEqual"));
  const fn = body.slice(0, body.indexOf("\n}\n"));
  assert(fn.includes('crypto.subtle.digest("SHA-256"'), "no longer hashes both sides");
  assertEquals(fn.match(/return /g)?.length, 1, "has more than one return, so it can bail early");
});

Deno.test("the service-role key is let in", async () => {
  assert(await isServiceRoleRequest(withAuth(`Bearer ${KEY}`), KEY));
});

Deno.test("a signed-in user's token, the anon key, the bare key or nothing is not", async () => {
  assertEquals(await isServiceRoleRequest(withAuth("Bearer eyJ.user.token"), KEY), false);
  assertEquals(await isServiceRoleRequest(withAuth(null), KEY), false);
  assertEquals(await isServiceRoleRequest(withAuth(KEY), KEY), false);
  assertEquals(await isServiceRoleRequest(withAuth(`Bearer ${KEY}x`), KEY), false);
});

Deno.test("an unset key refuses everyone, including a caller who sends 'Bearer undefined'", async () => {
  assertEquals(await isServiceRoleRequest(withAuth("Bearer undefined"), undefined), false);
  assertEquals(await isServiceRoleRequest(withAuth("Bearer "), ""), false);
});

// The guard is only worth anything if it runs before the queue is read. Checked on the source,
// because index.ts serves on import.
Deno.test("purge-r2-objects checks the caller before it reads the queue", async () => {
  const source = await Deno.readTextFile(new URL("../purge-r2-objects/index.ts", import.meta.url));
  const guard = source.indexOf("isServiceRoleRequest(req");
  const read = source.indexOf('.from("pending_object_deletions")');
  assert(guard !== -1, "index.ts no longer calls isServiceRoleRequest");
  assert(read !== -1, "index.ts no longer reads pending_object_deletions");
  assert(guard < read, "the queue is read before the caller is checked");
});

// userSession: the client must carry the caller's own header (so RLS sees them), and a token the
// auth server rejects must come back as no user rather than throwing.
Deno.test("userSession forwards the caller's token and returns the user auth hands back", async () => {
  const seen: { url: string; authorization: string | null; apikey: string | null }[] = [];
  const realFetch = globalThis.fetch;
  globalThis.fetch = (input: RequestInfo | URL, init?: RequestInit) => {
    const req = new Request(input, init);
    seen.push({ url: req.url, authorization: req.headers.get("Authorization"), apikey: req.headers.get("apikey") });
    const ok = req.headers.get("Authorization") === "Bearer good-token";
    return Promise.resolve(
      ok
        ? Response.json({ id: "aaaa0000-0000-4000-8000-00000000000a", aud: "authenticated", role: "authenticated" })
        : Response.json({ code: 401, error_code: "bad_jwt", msg: "invalid JWT" }, { status: 401 }),
    );
  };
  try {
    const env = { SUPABASE_URL: "http://127.0.0.1:54321", SUPABASE_ANON_KEY: "anon-key-for-tests" };
    const realGet = Deno.env.get;
    // deno-lint-ignore no-explicit-any
    (Deno.env as any).get = (k: string) => env[k as keyof typeof env] ?? realGet.call(Deno.env, k);
    try {
      const good = await userSession(withAuth("Bearer good-token"));
      assertEquals(good.user?.id, "aaaa0000-0000-4000-8000-00000000000a");
      assert(good.userClient, "no client returned");
      assertEquals(seen[0].url, "http://127.0.0.1:54321/auth/v1/user");
      assertEquals(seen[0].authorization, "Bearer good-token");
      assertEquals(seen[0].apikey, "anon-key-for-tests");

      const bad = await userSession(withAuth("Bearer stale-token"));
      assertEquals(bad.user, null);

      const none = await userSession(withAuth(null));
      assertEquals(none.user, null);
    } finally {
      // deno-lint-ignore no-explicit-any
      (Deno.env as any).get = realGet;
    }
  } finally {
    globalThis.fetch = realFetch;
  }
});
