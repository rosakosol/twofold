// Minimal HTTP/2 APNs token-auth sender. Sandbox and production use *separate* signing
// identities (Apple issues a distinct key per APNs environment) — this file was originally
// written expecting one shared key/team, then updated once real credentials existed:
// APNS_KEY_ID_SANDBOX / APNS_KEY_ID_PRODUCTION and APNS_PRIVATE_KEY_BASE64_SANDBOX /
// APNS_PRIVATE_KEY_BASE64_PRODUCTION, plus APNS_TEAM_ID and APNS_BUNDLE_ID (shared across both —
// the team and bundle identifier don't change per environment). Still a safe no-op (logged, never
// thrown) if any of an environment's required secrets are missing.
//
// Signs a short-lived ES256 JWT per Apple's token-auth scheme and caches it per environment for
// ~55 minutes (Apple tokens are valid up to 1 hour) rather than re-signing on every send.

import { importPKCS8, type KeyLike, SignJWT } from "npm:jose@^5";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

type ApnsEnvironment = "sandbox" | "production";

const TOKEN_TTL_MS = 55 * 60 * 1000;

const tokenCache = new Map<ApnsEnvironment, { jwt: string; signedAt: number }>();
const keyCache = new Map<ApnsEnvironment, KeyLike>();

function keyIdSecretName(environment: ApnsEnvironment): string {
  return environment === "sandbox" ? "APNS_KEY_ID_SANDBOX" : "APNS_KEY_ID_PRODUCTION";
}

function privateKeySecretName(environment: ApnsEnvironment): string {
  return environment === "sandbox" ? "APNS_PRIVATE_KEY_BASE64_SANDBOX" : "APNS_PRIVATE_KEY_BASE64_PRODUCTION";
}

function hasApnsConfig(environment: ApnsEnvironment): boolean {
  return Boolean(
    Deno.env.get(keyIdSecretName(environment)) &&
      Deno.env.get("APNS_TEAM_ID") &&
      Deno.env.get(privateKeySecretName(environment)) &&
      Deno.env.get("APNS_BUNDLE_ID"),
  );
}

/// Apple's .p8 key is normally downloaded as PEM text. Handles whichever of these the secret
/// actually holds, so a mismatch in how it was encoded doesn't silently produce an unusable key:
///   1. The raw PEM text itself (no base64 wrapping at all)
///   2. Base64 of the *entire* PEM text (e.g. `base64 -i AuthKey_XXXX.p8`) — the common case
///   3. Base64 of just the raw DER key bytes, with no PEM armor — wrapped back into PEM here
function normalizeToPem(secretValue: string): string {
  const trimmed = secretValue.trim();
  if (trimmed.includes("-----BEGIN")) return trimmed;

  try {
    const decoded = atob(trimmed);
    if (decoded.includes("-----BEGIN")) return decoded;
  } catch {
    // Not valid base64 — fall through and treat the original value as raw key bytes below.
  }

  const body = trimmed.match(/.{1,64}/g)?.join("\n") ?? trimmed;
  return `-----BEGIN PRIVATE KEY-----\n${body}\n-----END PRIVATE KEY-----`;
}

async function getSigningKey(environment: ApnsEnvironment): Promise<KeyLike> {
  const cached = keyCache.get(environment);
  if (cached) return cached;

  const pem = normalizeToPem(Deno.env.get(privateKeySecretName(environment))!);
  const key = await importPKCS8(pem, "ES256");
  keyCache.set(environment, key);
  return key;
}

async function getApnsJwt(environment: ApnsEnvironment): Promise<string> {
  const now = Date.now();
  const cached = tokenCache.get(environment);
  if (cached && now - cached.signedAt < TOKEN_TTL_MS) {
    return cached.jwt;
  }

  const keyId = Deno.env.get(keyIdSecretName(environment))!;
  const teamId = Deno.env.get("APNS_TEAM_ID")!;
  const privateKey = await getSigningKey(environment);

  const jwt = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyId })
    .setIssuer(teamId)
    .setIssuedAt()
    .sign(privateKey);

  tokenCache.set(environment, { jwt, signedAt: now });
  return jwt;
}

/// Diagnostic only — reports whether each environment's secrets are present and whether the
/// private key actually parses as a valid ES256 key, without ever returning key material or an
/// APNs token. Used by aeroapi-webhook's token-gated `?diag=apns` branch to sanity-check the
/// APNS_PRIVATE_KEY_BASE64_* encoding assumption against the real secrets post-setup.
export async function diagnoseApnsConfig(): Promise<Record<ApnsEnvironment, { configured: boolean; keyParses: boolean; error?: string }>> {
  const result = {} as Record<ApnsEnvironment, { configured: boolean; keyParses: boolean; error?: string }>;
  for (const environment of ["sandbox", "production"] as ApnsEnvironment[]) {
    const configured = hasApnsConfig(environment);
    if (!configured) {
      result[environment] = { configured: false, keyParses: false };
      continue;
    }
    try {
      await getSigningKey(environment);
      result[environment] = { configured: true, keyParses: true };
    } catch (err) {
      result[environment] = { configured: true, keyParses: false, error: (err as Error).message };
    }
  }
  return result;
}

/// What happened to one push. `ok` is Apple's 200. `tokenDead` means Apple said the token will
/// never work again (410, or 400 BadDeviceToken / Unregistered); the sender has already deleted it
/// by the time this returns. `skipped` is a send that never left because the environment's secrets
/// aren't configured.
export interface ApnsResult {
  ok: boolean;
  status: number | null;
  reason: string | null;
  tokenDead: boolean;
  skipped?: boolean;
}

/// One retry for a 429 or a 5xx (or a network error), after Apple's `Retry-After` when it gives one
/// and it is short, else `delayMs`. Exported so tests can set the delay to zero. Kept to a single
/// retry because the callers are cron fan-outs: a backlog of slow retries would push the rest of
/// the run past its slot.
export const APNS_RETRY = { delayMs: 1000, maxRetryAfterMs: 5000 };

/// Apple's reasons for a token that will never work again. 410 always means this too. Anything
/// else (a bad topic, an expired provider token, a too-big payload) is a problem on this side and
/// must not cost anybody their device registration.
// Not `ExpiredToken`: despite the name that is *our* provider JWT, not the device token.
const DEAD_TOKEN_REASONS = new Set(["BadDeviceToken", "Unregistered"]);

function isDeadToken(status: number, reason: string | null): boolean {
  if (status === 410) return true;
  return status === 400 && reason !== null && DEAD_TOKEN_REASONS.has(reason);
}

function isTransient(status: number): boolean {
  return status === 429 || status >= 500;
}

let pruneClient: SupabaseClient | null | undefined;

/// The service client the sender deletes dead tokens with. Imported lazily, as api-usage.ts does,
/// so this module still loads (and tests) where supabase-js cannot be resolved. Null when the
/// environment has no service key, in which case a dead token is only logged.
async function tokenStore(): Promise<SupabaseClient | null> {
  if (pruneClient !== undefined) return pruneClient;
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    pruneClient = null;
    return pruneClient;
  }
  const { createClient } = await import("jsr:@supabase/supabase-js@2");
  pruneClient = createClient(url, key);
  return pruneClient;
}

/// Forgets a token Apple has retired, so no later fan-out pays for a request to it. Never throws:
/// the push itself is already over, and a failed delete just means one more doomed send next time.
async function retireToken(table: "device_push_tokens" | "live_activity_push_tokens", column: string, token: string) {
  try {
    const db = await tokenStore();
    if (!db) {
      console.warn(`[apns] dead token not removed from ${table}: no service key in this environment`);
      return;
    }
    const { error } = await db.from(table).delete().eq(column, token);
    if (error) console.error(`[apns] could not remove dead token from ${table}:`, error.message);
  } catch (err) {
    console.error(`[apns] could not remove dead token from ${table}:`, (err as Error).message);
  }
}

async function readReason(res: Response): Promise<string | null> {
  try {
    const body = await res.json();
    return typeof body?.reason === "string" ? body.reason : null;
  } catch {
    return null;
  }
}

function retryDelayMs(res: Response | null): number {
  const header = res?.headers.get("retry-after");
  const seconds = header ? Number(header) : NaN;
  if (Number.isFinite(seconds) && seconds >= 0) return Math.min(seconds * 1000, APNS_RETRY.maxRetryAfterMs);
  return APNS_RETRY.delayMs;
}

/// Posts one push and reads Apple's answer: retries once on 429/5xx, re-signs on 403, and deletes
/// the token on a dead-token answer.
async function deliver(
  label: string,
  environment: ApnsEnvironment,
  token: string,
  headers: Record<string, string>,
  body: string,
  store: { table: "device_push_tokens" | "live_activity_push_tokens"; column: string },
): Promise<ApnsResult> {
  const host = environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  let jwt: string;
  try {
    jwt = await getApnsJwt(environment);
  } catch (err) {
    console.error(`[apns] ${label} could not sign (${environment}):`, (err as Error).message);
    return { ok: false, status: null, reason: (err as Error).message, tokenDead: false };
  }

  let last: ApnsResult = { ok: false, status: null, reason: null, tokenDead: false };
  for (let attempt = 0; attempt < 2; attempt++) {
    let res: Response;
    try {
      res = await fetch(`https://${host}/3/device/${token}`, {
        method: "POST",
        headers: { ...headers, authorization: `bearer ${jwt}` },
        body,
      });
    } catch (err) {
      console.error(`[apns] ${label} threw (${environment}):`, (err as Error).message);
      last = { ok: false, status: null, reason: (err as Error).message, tokenDead: false };
      if (attempt === 0) {
        await new Promise((r) => setTimeout(r, APNS_RETRY.delayMs));
        continue;
      }
      return last;
    }

    if (res.ok) {
      await res.body?.cancel();
      return { ok: true, status: res.status, reason: null, tokenDead: false };
    }

    const reason = await readReason(res);
    console.error(`[apns] ${label} failed with status ${res.status}${reason ? ` (${reason})` : ""} (${environment})`);
    // A stale/invalid cached JWT (e.g. Apple rejected it) shouldn't poison every subsequent
    // send until the 55-minute TTL naturally expires — clear it so the next call re-signs.
    if (res.status === 403) tokenCache.delete(environment);

    if (isDeadToken(res.status, reason)) {
      await retireToken(store.table, store.column, token);
      return { ok: false, status: res.status, reason, tokenDead: true };
    }

    last = { ok: false, status: res.status, reason, tokenDead: false };
    if (attempt === 0 && isTransient(res.status)) {
      await new Promise((r) => setTimeout(r, retryDelayMs(res)));
      continue;
    }
    return last;
  }
  return last;
}

export async function sendAPNs(
  deviceToken: string,
  environment: ApnsEnvironment,
  title: string,
  body: string,
  data?: Record<string, unknown>,
): Promise<ApnsResult> {
  if (!hasApnsConfig(environment)) {
    console.log(`[apns] skipping send — ${environment} APNs secrets not configured yet`);
    return { ok: false, status: null, reason: "not configured", tokenDead: false, skipped: true };
  }

  // Custom deep-link data (e.g. session id/game type) lives as top-level keys alongside `aps`,
  // not nested inside it — that's the payload shape APNs/UNNotification expect for anything
  // the receiving app wants to read out of `userInfo`.
  return await deliver(
    "send",
    environment,
    deviceToken,
    {
      "apns-topic": Deno.env.get("APNS_BUNDLE_ID")!,
      "apns-push-type": "alert",
      "content-type": "application/json",
    },
    JSON.stringify({ aps: { alert: { title, body }, sound: "default" }, ...data }),
    { table: "device_push_tokens", column: "apns_token" },
  );
}

// ---------------------------------------------------------------------------
// Fan-out bookkeeping
// ---------------------------------------------------------------------------
//
// Every caller of sendAPNs loops over a profile's `device_push_tokens` and, until this existed,
// dropped the result on the floor. A run where Apple refused every push logged and returned the
// same as one where every push landed, and notify-game-turn reported the phones it *tried* as
// `sent`. Callers now push through `pushToDevice`, which logs each failure with enough context to
// find the device and keeps a tally the caller puts in its logs and response.

/// A `device_push_tokens` row, as every caller selects it. `profile_id` is optional because not
/// every caller selects it; it's only used to say whose phone failed.
export interface PushTarget {
  apns_token: string;
  environment: ApnsEnvironment;
  profile_id?: string;
}

/// What a fan-out did. `failed` counts every push that was attempted and not delivered. Two
/// subsets of it say what to do next: `retired` pushes went to tokens Apple has given up on (now
/// deleted, nothing to retry), and `retryable` ones hit a 429, a 5xx or a network error that
/// outlasted the sender's own retry, so a later attempt may well land. `skipped` sends never left,
/// because this environment has no APNs secrets, and they're not failures.
export interface PushTally {
  attempted: number;
  sent: number;
  failed: number;
  retired: number;
  retryable: number;
  skipped: number;
}

export function newPushTally(): PushTally {
  return { attempted: 0, sent: 0, failed: 0, retired: 0, retryable: 0, skipped: 0 };
}

/// Folds `from` into `into`, for a run that keeps one tally per recipient and one overall.
export function addPushTally(into: PushTally, from: PushTally): PushTally {
  into.attempted += from.attempted;
  into.sent += from.sent;
  into.failed += from.failed;
  into.retired += from.retired;
  into.retryable += from.retryable;
  into.skipped += from.skipped;
  return into;
}

/// "2/3 sent, 1 failed (1 retired)", for a run's summary line.
export function describePushTally(t: PushTally): string {
  const parts = [`${t.sent}/${t.attempted} sent`];
  if (t.failed > 0) {
    const why = [t.retired > 0 ? `${t.retired} retired` : "", t.retryable > 0 ? `${t.retryable} retryable` : ""]
      .filter(Boolean)
      .join(", ");
    parts.push(`${t.failed} failed${why ? ` (${why})` : ""}`);
  }
  if (t.skipped > 0) parts.push(`${t.skipped} skipped (APNs not configured)`);
  return parts.join(", ");
}

function isRetryable(result: ApnsResult): boolean {
  if (result.ok || result.tokenDead || result.skipped) return false;
  return result.status === null || isTransient(result.status);
}

/// Enough of a token to tell two of one person's phones apart in a log, and no more: the whole
/// token is what a push is addressed to.
function tokenTail(token: string): string {
  return `…${token.slice(-6)}`;
}

/// Sends one push through `sendAPNs`, records the outcome in `tally`, and logs a failure under
/// `caller`'s own prefix with the profile, the token's tail and Apple's answer. Never throws: one
/// bad push must not end the fan-out for everyone after it.
export async function pushToDevice(
  caller: string,
  tally: PushTally,
  target: PushTarget,
  title: string,
  body: string,
  data?: Record<string, unknown>,
): Promise<ApnsResult> {
  let result: ApnsResult;
  try {
    result = await sendAPNs(target.apns_token, target.environment, title, body, data);
  } catch (err) {
    result = { ok: false, status: null, reason: (err as Error).message, tokenDead: false };
  }

  tally.attempted++;
  if (result.ok) {
    tally.sent++;
    return result;
  }
  if (result.skipped) {
    tally.skipped++;
    return result;
  }

  tally.failed++;
  if (result.tokenDead) tally.retired++;
  if (isRetryable(result)) tally.retryable++;

  const who = `${target.profile_id ? `profile ${target.profile_id}, ` : ""}device ${tokenTail(target.apns_token)}, ${target.environment}`;
  const answer = `${result.status ?? "no response"}${result.reason ? ` ${result.reason}` : ""}`;
  const outcome = result.tokenDead
    ? "token retired"
    : isRetryable(result)
    ? "transient, a later attempt may land"
    : "rejected";
  const line = `[${caller}] push not delivered (${who}): ${answer} — ${outcome}`;
  if (result.tokenDead) console.warn(line);
  else console.error(line);
  return result;
}

/// Seconds between the Unix epoch (1970-01-01) and the Cocoa reference date (2001-01-01) —
/// Swift's default JSONDecoder decodes `Date` fields as seconds since the *Cocoa* reference
/// date, not Unix epoch. Every Date field inside a Live Activity's `content-state` must be
/// converted with this before being sent; `aps.timestamp`/`stale-date`/`dismissal-date`
/// themselves stay plain Unix seconds — do not run those through this helper.
const COCOA_EPOCH_OFFSET_SECONDS = 978_307_200;

export function toCocoaTimestamp(date: Date): number {
  return Math.round(date.getTime() / 1000) - COCOA_EPOCH_OFFSET_SECONDS;
}

/// Sends a Live Activity content-state update (or ends the Activity) — distinct push type from
/// `sendAPNs`'s plain alert notifications: different topic suffix, different payload shape
/// (`content-state` instead of `alert`), and the push token here is per-*Activity*
/// (`live_activity_push_tokens.push_token`, from `activity.pushTokenUpdates` client-side), not
/// a per-device token. Reuses the same JWT signing/caching as `sendAPNs` — only headers/topic/
/// body differ between push types.
export async function sendLiveActivityUpdate(
  pushToken: string,
  environment: ApnsEnvironment,
  contentState: Record<string, unknown>,
  event: "update" | "end",
  opts?: { alert?: { title: string; body: string }; staleDateUnix?: number; dismissalDateUnix?: number },
): Promise<ApnsResult> {
  if (!hasApnsConfig(environment)) {
    console.log(`[apns] skipping live activity send — ${environment} APNs secrets not configured yet`);
    return { ok: false, status: null, reason: "not configured", tokenDead: false, skipped: true };
  }

  const aps: Record<string, unknown> = {
    timestamp: Math.round(Date.now() / 1000),
    event,
    "content-state": contentState,
  };
  if (opts?.alert) aps.alert = opts.alert;
  if (opts?.staleDateUnix) aps["stale-date"] = opts.staleDateUnix;
  if (opts?.dismissalDateUnix) aps["dismissal-date"] = opts.dismissalDateUnix;

  return await deliver(
    "live activity send",
    environment,
    pushToken,
    {
      "apns-topic": `${Deno.env.get("APNS_BUNDLE_ID")!}.push-type.liveactivity`,
      "apns-push-type": "liveactivity",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    JSON.stringify({ aps }),
    { table: "live_activity_push_tokens", column: "push_token" },
  );
}
