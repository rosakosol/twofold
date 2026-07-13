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

import { importPKCS8, SignJWT } from "npm:jose@^5";

type ApnsEnvironment = "sandbox" | "production";

const TOKEN_TTL_MS = 55 * 60 * 1000;

const tokenCache = new Map<ApnsEnvironment, { jwt: string; signedAt: number }>();
const keyCache = new Map<ApnsEnvironment, CryptoKey>();

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

async function getSigningKey(environment: ApnsEnvironment): Promise<CryptoKey> {
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

export async function sendAPNs(
  deviceToken: string,
  environment: ApnsEnvironment,
  title: string,
  body: string,
  data?: Record<string, unknown>,
): Promise<void> {
  if (!hasApnsConfig(environment)) {
    console.log(`[apns] skipping send — ${environment} APNs secrets not configured yet`);
    return;
  }

  try {
    const jwt = await getApnsJwt(environment);
    const bundleId = Deno.env.get("APNS_BUNDLE_ID")!;
    const host = environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";

    // Custom deep-link data (e.g. session id/game type) lives as top-level keys alongside `aps`,
    // not nested inside it — that's the payload shape APNs/UNNotification expect for anything
    // the receiving app wants to read out of `userInfo`.
    const res = await fetch(`https://${host}/3/device/${deviceToken}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": bundleId,
        "apns-push-type": "alert",
        "content-type": "application/json",
      },
      body: JSON.stringify({ aps: { alert: { title, body }, sound: "default" }, ...data }),
    });

    if (!res.ok) {
      console.error(`[apns] send failed with status ${res.status} (${environment})`);
      await res.arrayBuffer().catch(() => undefined);
      // A stale/invalid cached JWT (e.g. Apple rejected it) shouldn't poison every subsequent
      // send until the 55-minute TTL naturally expires — clear it so the next call re-signs.
      if (res.status === 403) tokenCache.delete(environment);
    }
  } catch (err) {
    console.error(`[apns] send threw (${environment}):`, (err as Error).message);
  }
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
): Promise<void> {
  if (!hasApnsConfig(environment)) {
    console.log(`[apns] skipping live activity send — ${environment} APNs secrets not configured yet`);
    return;
  }

  try {
    const jwt = await getApnsJwt(environment);
    const bundleId = Deno.env.get("APNS_BUNDLE_ID")!;
    const host = environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";

    const aps: Record<string, unknown> = {
      timestamp: Math.round(Date.now() / 1000),
      event,
      "content-state": contentState,
    };
    if (opts?.alert) aps.alert = opts.alert;
    if (opts?.staleDateUnix) aps["stale-date"] = opts.staleDateUnix;
    if (opts?.dismissalDateUnix) aps["dismissal-date"] = opts.dismissalDateUnix;

    const res = await fetch(`https://${host}/3/device/${pushToken}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": `${bundleId}.push-type.liveactivity`,
        "apns-push-type": "liveactivity",
        "apns-priority": "10",
        "content-type": "application/json",
      },
      body: JSON.stringify({ aps }),
    });

    if (!res.ok) {
      console.error(`[apns] live activity send failed with status ${res.status} (${environment})`);
      await res.arrayBuffer().catch(() => undefined);
      if (res.status === 403) tokenCache.delete(environment);
    }
  } catch (err) {
    console.error(`[apns] live activity send threw (${environment}):`, (err as Error).message);
  }
}
