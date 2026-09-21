// What an incoming Zoho webhook payload MEANS, with no Deno.serve and no network.
//
// Split out of index.ts for the same reason revenuecat-webhook/subscriber.ts was: that module calls
// `Deno.serve` at import time, so importing it from a test starts a server. Everything here is a
// pure function over a string, and every one of those strings was written by a stranger.

/// Our own addresses. Mail from any of these is our own notification coming back to us.
export function isOurOwnAddress(address: string): boolean {
  const normalised = address.trim().toLowerCase();
  const ours = [
    Deno.env.get("ZOHO_FROM_ADDRESS")?.toLowerCase(),
    Deno.env.get("ZOHO_SMTP_USER")?.toLowerCase(),
    "support@twofoldapp.com.au",
    "hello@twofoldapp.com.au",
  ].filter(Boolean) as string[];
  return ours.some((a) => normalised === a || normalised.endsWith(`<${a}>`));
}

/// `fromAddress` arrives as either `someone@example.com` or `Their Name <someone@example.com>`.
export function parseFrom(raw: string): { email: string; name: string | null } {
  const value = (raw ?? "").trim();
  const angled = value.match(/^(.*?)\s*<([^>]+)>$/);
  if (angled) {
    const name = angled[1].replace(/^["']|["']$/g, "").trim();
    return { email: angled[2].trim().toLowerCase(), name: name || null };
  }
  return { email: value.toLowerCase(), name: null };
}

/// Zoho sends `summary` (a plain-text preview, which can be truncated) and `html`. Prefer whichever
/// carries more, stripping tags from the HTML — a support queue wants the words, and rendering
/// arbitrary sender-controlled HTML in the console would be a stored-XSS surface for the price of
/// some formatting.
export function extractBody(summary: string | undefined, html: string | undefined): string {
  const plain = (summary ?? "").trim();
  const stripped = (html ?? "")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/p>/gi, "\n\n")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/[ \t]+/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
  return stripped.length > plain.length ? stripped : plain;
}

/// Zoho reports `receivedTime`/`sentDateInGMT` as epoch milliseconds, sometimes as a string.
export function parseReceived(value: unknown): string {
  const ms = typeof value === "number" ? value : typeof value === "string" ? Number(value) : NaN;
  if (Number.isFinite(ms) && ms > 0) return new Date(ms).toISOString();
  return new Date().toISOString();
}

export async function signatureMatches(body: string, provided: string, secret: string): Promise<boolean> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body));
  const expected = btoa(String.fromCharCode(...new Uint8Array(mac)));
  // Length-independent compare, so a mismatch does not leak where it diverged via timing.
  if (expected.length !== provided.length) return false;
  let diff = 0;
  for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ provided.charCodeAt(i);
  return diff === 0;
}
