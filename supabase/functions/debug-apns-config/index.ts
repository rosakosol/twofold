// Temporary diagnostic — reports whether each APNs environment's secrets are present/parse
// correctly, and does a real test send to the most-recently-registered device tokens so the
// actual Apple response status/body is visible (sendAPNs itself only logs this, invisible to us
// without function log access). Delete once game notifications are confirmed working again.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { diagnoseApnsConfig } from "../_shared/apns.ts";
import { importPKCS8, SignJWT } from "npm:jose@^5";

function normalizeToPem(secretValue: string): string {
  const trimmed = secretValue.trim();
  if (trimmed.includes("-----BEGIN")) return trimmed;
  try {
    const decoded = atob(trimmed);
    if (decoded.includes("-----BEGIN")) return decoded;
  } catch { /* fall through */ }
  const body = trimmed.match(/.{1,64}/g)?.join("\n") ?? trimmed;
  return `-----BEGIN PRIVATE KEY-----\n${body}\n-----END PRIVATE KEY-----`;
}

Deno.serve(async () => {
  const config = await diagnoseApnsConfig();

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: tokens, error: tokenError } = await serviceClient
    .from("device_push_tokens")
    .select("apns_token, environment, created_at, profile_id")
    .order("created_at", { ascending: false })
    .limit(3);

  if (tokenError || !tokens || tokens.length === 0) {
    return Response.json({ config, tokenError: tokenError?.message ?? "no tokens found" });
  }

  const results = [];
  for (const row of tokens) {
    const environment = row.environment as "sandbox" | "production";
    try {
      const keyIdName = environment === "sandbox" ? "APNS_KEY_ID_SANDBOX" : "APNS_KEY_ID_PRODUCTION";
      const privateKeyName = environment === "sandbox" ? "APNS_PRIVATE_KEY_BASE64_SANDBOX" : "APNS_PRIVATE_KEY_BASE64_PRODUCTION";
      const keyId = Deno.env.get(keyIdName)!;
      const teamId = Deno.env.get("APNS_TEAM_ID")!;
      const bundleId = Deno.env.get("APNS_BUNDLE_ID")!;
      const pem = normalizeToPem(Deno.env.get(privateKeyName)!);
      const privateKey = await importPKCS8(pem, "ES256");
      const jwt = await new SignJWT({}).setProtectedHeader({ alg: "ES256", kid: keyId }).setIssuer(teamId).setIssuedAt().sign(privateKey);

      const host = environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
      const res = await fetch(`https://${host}/3/device/${row.apns_token}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${jwt}`,
          "apns-topic": bundleId,
          "apns-push-type": "alert",
          "content-type": "application/json",
        },
        body: JSON.stringify({ aps: { alert: { title: "Diagnostic", body: "Twofold APNs test send" }, sound: "default" } }),
      });
      const responseBody = await res.text().catch(() => "");
      results.push({
        profileId: row.profile_id, environment, tokenPrefix: row.apns_token.slice(0, 12),
        status: res.status, ok: res.ok, responseBody, bundleIdUsed: bundleId,
      });
    } catch (err) {
      results.push({ profileId: row.profile_id, environment, error: (err as Error).message });
    }
  }

  return Response.json({ config, results });
});
