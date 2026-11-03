// What the sender does with Apple's answer. fetch is stubbed: requests to Apple get the canned
// responses each test queues, and requests to PostgREST (the dead-token delete) are recorded.

import { assert, assertEquals } from "jsr:@std/assert@1";
import { addPushTally, APNS_RETRY, newPushTally, pushToDevice, sendAPNs, sendLiveActivityUpdate } from "./apns.ts";

const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
const ENV: Record<string, string> = {
  APNS_KEY_ID_SANDBOX: "KEYID12345",
  APNS_PRIVATE_KEY_BASE64_SANDBOX: btoa(String.fromCharCode(...pkcs8)),
  APNS_TEAM_ID: "TEAM123456",
  APNS_BUNDLE_ID: "app.twofold.test",
  SUPABASE_URL: "http://db.test",
  SUPABASE_SERVICE_ROLE_KEY: "service-role-key-for-tests",
};

interface Seen {
  method: string;
  url: URL;
}

let seen: Seen[] = [];
let apple: (() => Response | Promise<Response>)[] = [];

function reply(status: number, reason?: string, headers?: Record<string, string>): () => Response {
  return () => new Response(reason ? JSON.stringify({ reason }) : null, { status, headers });
}

const realFetch = globalThis.fetch;
const realGet = Deno.env.get;

function install() {
  seen = [];
  apple = [];
  APNS_RETRY.delayMs = 0;
  // deno-lint-ignore no-explicit-any
  (Deno.env as any).get = (key: string) => ENV[key] ?? realGet.call(Deno.env, key);
  globalThis.fetch = (input: RequestInfo | URL, init?: RequestInit) => {
    const req = new Request(input, init);
    const url = new URL(req.url);
    seen.push({ method: req.method, url });
    if (url.host === "db.test") return Promise.resolve(new Response(null, { status: 204 }));
    const next = apple.shift();
    if (!next) return Promise.reject(new Error(`unexpected request to ${url}`));
    return Promise.resolve(next());
  };
}

function restore() {
  globalThis.fetch = realFetch;
  // deno-lint-ignore no-explicit-any
  (Deno.env as any).get = realGet;
}

async function run(fn: () => Promise<void>) {
  install();
  try {
    await fn();
  } finally {
    restore();
  }
}

const toApple = () => seen.filter((s) => s.url.host === "api.sandbox.push.apple.com");
const deletes = () => seen.filter((s) => s.url.host === "db.test" && s.method === "DELETE");

Deno.test("a delivered push reports ok and touches no token", () =>
  run(async () => {
    apple.push(reply(200));
    const result = await sendAPNs("tok-ok", "sandbox", "Hi", "There");
    assertEquals(result.ok, true);
    assertEquals(result.tokenDead, false);
    assertEquals(toApple().length, 1);
    assertEquals(deletes(), []);
  }));

for (const [status, reason] of [[410, "Unregistered"], [400, "BadDeviceToken"], [400, "Unregistered"]] as const) {
  Deno.test(`${status} ${reason}: the device token is deleted`, () =>
    run(async () => {
      apple.push(reply(status, reason));
      const result = await sendAPNs("tok-dead", "sandbox", "Hi", "There");
      assertEquals(result.ok, false);
      assertEquals(result.tokenDead, true);
      assertEquals(result.status, status);
      assertEquals(result.reason, reason);
      assertEquals(toApple().length, 1, "a dead token was retried");
      const del = deletes();
      assertEquals(del.length, 1, "the dead token was not deleted");
      assertEquals(del[0].url.pathname, "/rest/v1/device_push_tokens");
      assertEquals(del[0].url.searchParams.get("apns_token"), "eq.tok-dead");
    }));
}

// Problems on this side must never cost anybody their registration.
for (const [status, reason] of [[400, "BadTopic"], [403, "ExpiredProviderToken"], [400, "PayloadTooLarge"], [413, "PayloadTooLarge"]] as const) {
  Deno.test(`${status} ${reason}: reported, not retried, and the token is kept`, () =>
    run(async () => {
      apple.push(reply(status, reason));
      const result = await sendAPNs("tok-keep", "sandbox", "Hi", "There");
      assertEquals(result.ok, false);
      assertEquals(result.tokenDead, false);
      assertEquals(result.reason, reason);
      assertEquals(toApple().length, 1);
      assertEquals(deletes(), []);
    }));
}

Deno.test("429 is retried once, honouring a short Retry-After", () =>
  run(async () => {
    APNS_RETRY.maxRetryAfterMs = 0;
    try {
      apple.push(reply(429, "TooManyRequests", { "retry-after": "1" }), reply(200));
      const result = await sendAPNs("tok-busy", "sandbox", "Hi", "There");
      assertEquals(result.ok, true);
      assertEquals(toApple().length, 2);
      assertEquals(deletes(), []);
    } finally {
      APNS_RETRY.maxRetryAfterMs = 5000;
    }
  }));

Deno.test("a 5xx that persists is retried once, then reported, and the token is kept", () =>
  run(async () => {
    apple.push(reply(503, "ServiceUnavailable"), reply(500, "InternalServerError"));
    const result = await sendAPNs("tok-down", "sandbox", "Hi", "There");
    assertEquals(result.ok, false);
    assertEquals(result.status, 500);
    assertEquals(result.tokenDead, false);
    assertEquals(toApple().length, 2);
    assertEquals(deletes(), []);
  }));

Deno.test("a network error is retried once", () =>
  run(async () => {
    apple.push(() => Promise.reject(new Error("connection reset")), reply(200));
    const result = await sendAPNs("tok-flaky", "sandbox", "Hi", "There");
    assertEquals(result.ok, true);
    assertEquals(toApple().length, 2);
  }));

Deno.test("a dead Live Activity token is deleted from live_activity_push_tokens", () =>
  run(async () => {
    apple.push(reply(410, "Unregistered"));
    const result = await sendLiveActivityUpdate("la-dead", "sandbox", { status: "landed" }, "update");
    assertEquals(result.tokenDead, true);
    const del = deletes();
    assertEquals(del.length, 1);
    assertEquals(del[0].url.pathname, "/rest/v1/live_activity_push_tokens");
    assertEquals(del[0].url.searchParams.get("push_token"), "eq.la-dead");
  }));

Deno.test("unconfigured environments are skipped, not sent", () =>
  run(async () => {
    const result = await sendAPNs("tok", "production", "Hi", "There");
    assertEquals(result.skipped, true);
    assertEquals(result.ok, false);
    assert(seen.length === 0);
  }));

// ---------------------------------------------------------------------------
// pushToDevice: what every fan-out does with each result
// ---------------------------------------------------------------------------
//
// sendAPNs reports what Apple said and every caller used to drop it, so a run where nothing was
// delivered logged and returned exactly what a run where everything was delivered did.

function captureLogs(): { lines: string[]; restore: () => void } {
  const lines: string[] = [];
  const real = { error: console.error, warn: console.warn, log: console.log };
  console.error = (...args: unknown[]) => lines.push(args.map(String).join(" "));
  console.warn = (...args: unknown[]) => lines.push(args.map(String).join(" "));
  console.log = () => {};
  return { lines, restore: () => Object.assign(console, real) };
}

Deno.test("pushToDevice counts each outcome separately", () =>
  run(async () => {
    const out = captureLogs();
    try {
      apple.push(reply(200), reply(410, "Unregistered"), reply(503), reply(503), reply(400, "BadTopic"));
      const tally = newPushTally();
      const device = (apns_token: string) => ({ apns_token, environment: "sandbox" as const, profile_id: "p1" });
      await pushToDevice("test-caller", tally, device("tok-a"), "Hi", "There");
      await pushToDevice("test-caller", tally, device("tok-b"), "Hi", "There");
      await pushToDevice("test-caller", tally, device("tok-c"), "Hi", "There");
      await pushToDevice("test-caller", tally, device("tok-d"), "Hi", "There");
      // No production secrets in this environment, so this one never leaves.
      await pushToDevice("test-caller", tally, { apns_token: "tok-e", environment: "production" }, "Hi", "There");
      assertEquals(tally, { attempted: 5, sent: 1, failed: 3, retired: 1, retryable: 1, skipped: 1 });
    } finally {
      out.restore();
    }
  }));

Deno.test("pushToDevice logs a failure with the caller, the profile and Apple's answer", () =>
  run(async () => {
    const out = captureLogs();
    try {
      apple.push(reply(400, "BadTopic"));
      await pushToDevice(
        "send-streak-reminders",
        newPushTally(),
        { apns_token: "0123456789abcdef", environment: "sandbox", profile_id: "profile-42" },
        "Hi",
        "There",
      );
      const line = out.lines.find((l) => l.startsWith("[send-streak-reminders]"));
      assert(line, `no line from the caller in ${JSON.stringify(out.lines)}`);
      assert(line.includes("profile-42"), line);
      assert(line.includes("400") && line.includes("BadTopic"), line);
      assert(line.includes("…abcdef"), line);
      assert(!line.includes("0123456789"), `the whole token was logged: ${line}`);
    } finally {
      out.restore();
    }
  }));

Deno.test("a network failure that outlasts the retry is counted as retryable", () =>
  run(async () => {
    const out = captureLogs();
    try {
      apple.push(() => Promise.reject(new Error("reset")), () => Promise.reject(new Error("reset again")));
      const tally = newPushTally();
      const result = await pushToDevice("x", tally, { apns_token: "tok", environment: "sandbox" }, "Hi", "There");
      assertEquals(result.ok, false);
      assertEquals(tally, { attempted: 1, sent: 0, failed: 1, retired: 0, retryable: 1, skipped: 0 });
    } finally {
      out.restore();
    }
  }));

Deno.test("addPushTally sums two tallies", () => {
  const a = { attempted: 2, sent: 1, failed: 1, retired: 1, retryable: 0, skipped: 0 };
  const b = { attempted: 3, sent: 2, failed: 1, retired: 0, retryable: 1, skipped: 0 };
  addPushTally(a, b);
  assertEquals(a, { attempted: 5, sent: 3, failed: 2, retired: 1, retryable: 1, skipped: 0 });
});
