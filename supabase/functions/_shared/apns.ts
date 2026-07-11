// Minimal HTTP/2 APNs token-auth sender. Deliberately inert until real Apple Push credentials
// are configured: if APNS_KEY_ID / APNS_TEAM_ID / APNS_AUTH_KEY / APNS_BUNDLE_ID aren't all set,
// every call is a safe no-op (logged, never thrown) so the flight-sync pipeline never breaks on
// a missing push credential during early development.
//
// Signs a short-lived ES256 JWT per Apple's token-auth scheme and caches it for ~55 minutes
// (Apple tokens are valid up to 1 hour) rather than re-signing on every send.

import { importPKCS8, SignJWT } from "npm:jose@^5";

const TOKEN_TTL_MS = 55 * 60 * 1000;

let cachedToken: { jwt: string; signedAt: number } | null = null;

function hasApnsConfig(): boolean {
  return Boolean(
    Deno.env.get("APNS_KEY_ID") &&
      Deno.env.get("APNS_TEAM_ID") &&
      Deno.env.get("APNS_AUTH_KEY") &&
      Deno.env.get("APNS_BUNDLE_ID"),
  );
}

async function getApnsJwt(): Promise<string> {
  const now = Date.now();
  if (cachedToken && now - cachedToken.signedAt < TOKEN_TTL_MS) {
    return cachedToken.jwt;
  }

  const keyId = Deno.env.get("APNS_KEY_ID")!;
  const teamId = Deno.env.get("APNS_TEAM_ID")!;
  const authKeyPem = Deno.env.get("APNS_AUTH_KEY")!;

  const privateKey = await importPKCS8(authKeyPem, "ES256");
  const jwt = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyId })
    .setIssuer(teamId)
    .setIssuedAt()
    .sign(privateKey);

  cachedToken = { jwt, signedAt: now };
  return jwt;
}

export async function sendAPNs(
  deviceToken: string,
  environment: "sandbox" | "production",
  title: string,
  body: string,
): Promise<void> {
  if (!hasApnsConfig()) {
    console.log("[apns] skipping send — APNs secrets not configured yet");
    return;
  }

  try {
    const jwt = await getApnsJwt();
    const bundleId = Deno.env.get("APNS_BUNDLE_ID")!;
    const host = environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";

    const res = await fetch(`https://${host}/3/device/${deviceToken}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": bundleId,
        "apns-push-type": "alert",
        "content-type": "application/json",
      },
      body: JSON.stringify({ aps: { alert: { title, body }, sound: "default" } }),
    });

    if (!res.ok) {
      console.error(`[apns] send failed with status ${res.status}`);
      await res.arrayBuffer().catch(() => undefined);
    }
  } catch (err) {
    console.error("[apns] send threw:", (err as Error).message);
  }
}
