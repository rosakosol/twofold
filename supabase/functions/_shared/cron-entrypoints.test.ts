// The cron and trigger-invoked functions answer to the service role and nobody else.
//
// Each is `verify_jwt = true`, which reads like "only the cron can call this" and is not: the
// gateway accepts any valid JWT, and every signed-in user's access token is one. Before the guard
// in each handler, any account could drain the deletion queue on demand, sweep Zoho, or — worst —
// call `purge-r2-objects` with `{"dryRun": true}` and read back every queued key.
//
// These load the real `index.ts` with `Deno.serve` captured instead of listening, so what is
// tested is the handler that ships, not a copy of its first line.

import { assert, assertEquals } from "jsr:@std/assert@1";

const SERVICE_KEY = "service-role-key-for-tests";
const ENV: Record<string, string> = {
  SUPABASE_URL: "http://127.0.0.1:1",
  SUPABASE_ANON_KEY: "anon-key-for-tests",
  SUPABASE_SERVICE_ROLE_KEY: SERVICE_KEY,
  R2_ACCOUNT_ID: "acct",
  R2_ACCESS_KEY_ID: "id",
  R2_SECRET_ACCESS_KEY: "secret",
  R2_BUCKET: "bucket",
};

type Handler = (req: Request) => Response | Promise<Response>;

/// Every outbound request, so a test can tell whether the handler reached the database, Zoho or R2.
const outbound: string[] = [];

// Installed once, before any module is imported: each index.ts calls `Deno.serve` at top level.
// deno-lint-ignore no-explicit-any
const d = Deno as any;
d.env.get = (key: string) => ENV[key];
let captured: Handler | undefined;
d.serve = (handler: Handler) => {
  captured = handler;
  return { finished: Promise.resolve(), shutdown: () => Promise.resolve() };
};
globalThis.fetch = (input: RequestInfo | URL) => {
  outbound.push(String(input instanceof Request ? input.url : input));
  return Promise.resolve(new Response(JSON.stringify({ message: "stubbed" }), { status: 500 }));
};

/// Memoised: a module is evaluated once, so a second import would not call `Deno.serve` again.
const handlers = new Map<string, Handler>();

async function load(name: string): Promise<Handler> {
  const cached = handlers.get(name);
  if (cached) return cached;
  captured = undefined;
  await import(`../${name}/index.ts`);
  assert(captured, `${name} did not register a handler`);
  handlers.set(name, captured);
  return captured;
}

function post(authorization?: string): Request {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (authorization !== undefined) headers.Authorization = authorization;
  return new Request("http://localhost/", { method: "POST", headers, body: JSON.stringify({ dryRun: true }) });
}

// A syntactically real user access token. The gateway would accept it; the handler must not.
const USER_JWT = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9." +
  btoa(JSON.stringify({ sub: "aaaa0000-0000-4000-8000-00000000000a", role: "authenticated" })) + ".sig";

for (const name of ["purge-r2-objects", "purge-support-attachments", "fetch-support-attachments"]) {
  Deno.test(`${name}: a signed-in user's token is refused before anything is read`, async () => {
    const handler = await load(name);
    for (const auth of [USER_JWT, `Bearer ${ENV.SUPABASE_ANON_KEY}`, undefined, "Bearer "]) {
      outbound.length = 0;
      const res = await handler(post(auth));
      assertEquals(res.status, 403, `${name} accepted Authorization=${auth}`);
      assertEquals(outbound, [], `${name} reached out before refusing Authorization=${auth}`);
      await res.body?.cancel();
    }
  });

  Deno.test(`${name}: the service role gets past the guard`, async () => {
    const handler = await load(name);
    outbound.length = 0;
    const res = await handler(post(`Bearer ${SERVICE_KEY}`));
    // The stubbed backend fails, so the run itself errors — the point is that it got that far.
    assert(res.status !== 403, `${name} refused the service role`);
    assert(outbound.length > 0, `${name} never reached the database with the service role`);
    await res.body?.cancel();
  });
}

// Every function that answers to the service role alone, whichever form its check used to take.
const SERVICE_ROLE_ONLY = [
  "archive-stale-games",
  "fetch-support-attachments",
  "notify-game-turn",
  "purge-dormant-accounts",
  "purge-r2-objects",
  "purge-support-attachments",
  "reconcile-subscriptions",
  "refresh-due-flights",
  "send-birthday-reminders",
  "send-partner-invite-reminders",
  "send-streak-reminders",
  "send-welcome-emails",
];

for (const name of SERVICE_ROLE_ONLY) {
  Deno.test(`${name}: refuses a user's token, the anon key and no header, before reaching out`, async () => {
    const handler = await load(name);
    for (const auth of [USER_JWT, `Bearer ${ENV.SUPABASE_ANON_KEY}`, undefined, "Bearer ", SERVICE_KEY]) {
      outbound.length = 0;
      const res = await handler(post(auth));
      assert(res.status === 401 || res.status === 403, `${name} accepted Authorization=${auth} (${res.status})`);
      assertEquals(outbound, [], `${name} reached out before refusing Authorization=${auth}`);
      await res.body?.cancel();
    }
  });

  Deno.test(`${name}: the service-role key gets past the guard`, async () => {
    const handler = await load(name);
    const res = await handler(post(`Bearer ${SERVICE_KEY}`));
    // The stubbed backend fails, or the test body is not what the function wants; either way the
    // answer is not a refusal of the caller.
    assert(res.status !== 401 && res.status !== 403, `${name} refused the service role (${res.status})`);
    await res.body?.cancel();
  });

  // The inline copies built `Bearer ${Deno.env.get(...)}`, which is "Bearer undefined" when the key
  // is missing, and then let in anybody who sent exactly that.
  Deno.test(`${name}: with the key unset, "Bearer undefined" is refused`, async () => {
    const handler = await load(name);
    const saved = ENV.SUPABASE_SERVICE_ROLE_KEY;
    delete ENV.SUPABASE_SERVICE_ROLE_KEY;
    try {
      outbound.length = 0;
      const res = await handler(post("Bearer undefined"));
      assert(res.status === 401 || res.status === 403, `${name} let "Bearer undefined" in (${res.status})`);
      assertEquals(outbound, [], `${name} reached out for "Bearer undefined"`);
      await res.body?.cancel();
    } finally {
      ENV.SUPABASE_SERVICE_ROLE_KEY = saved;
    }
  });
}
