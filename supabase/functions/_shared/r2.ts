// Presigned URLs for Cloudflare R2, which speaks the S3 API and therefore AWS Signature V4.
//
// Why sign here rather than proxy the bytes: a presigned URL lets the phone fetch straight from
// R2, so image loads never pass through an Edge Function's CPU or Supabase's egress. That is the
// whole point of the move off Supabase Storage. The trade is that the signature *is* the
// credential — anyone holding a live URL can fetch that object until it expires — which is the
// same property Supabase's own `createSignedURL` had, and the reason expiries here are short.
//
// Query-string (presigned) signing, not the Authorization-header variant: the fetcher is
// `AsyncImage` on a phone, which sends a plain GET with no headers we control.
//
// Deliberately no dependency. The AWS SDK is tens of megabytes of JS for four HMACs, and every
// Edge Function cold start would pay for it. `r2.test.ts` checks this implementation against
// botocore's output for the same inputs, so "no dependency" does not mean "unverified".

/// R2 ignores the region but SigV4 requires one in the credential scope, and it must be the same
/// string on both sides. Cloudflare's documented value.
const REGION = "auto";
const SERVICE = "s3";
const ALGORITHM = "AWS4-HMAC-SHA256";

/// The longest a presigned URL may live, per the SigV4 spec. Nothing here asks for anywhere near
/// it — see the callers' own expiries — but a silently-truncated signature is worse than an error.
export const MAX_EXPIRES_IN = 604_800;

export interface R2Config {
  accountId: string;
  accessKeyId: string;
  secretAccessKey: string;
  bucket: string;
}

/// Reads the four secrets. Throws rather than returning a half-configured client: a function that
/// presigns with an empty secret produces URLs that fail at R2 with an opaque 403, and finding
/// that from the outside is miserable.
export function r2ConfigFromEnv(env: (key: string) => string | undefined = Deno.env.get): R2Config {
  const required = ["R2_ACCOUNT_ID", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY", "R2_BUCKET"];
  const missing = required.filter((key) => !env(key));
  if (missing.length > 0) {
    throw new Error(`R2 is not configured: missing ${missing.join(", ")}`);
  }
  return {
    accountId: env("R2_ACCOUNT_ID")!,
    accessKeyId: env("R2_ACCESS_KEY_ID")!,
    secretAccessKey: env("R2_SECRET_ACCESS_KEY")!,
    bucket: env("R2_BUCKET")!,
  };
}

export function r2Host(config: R2Config): string {
  return `${config.accountId}.r2.cloudflarestorage.com`;
}

/// RFC 3986, which is stricter than `encodeURIComponent`: that leaves `!'()*` alone and SigV4
/// requires them percent-encoded. A key containing an apostrophe would otherwise sign correctly
/// here and be rejected by R2, which canonicalises it the strict way.
function uriEncode(value: string): string {
  return encodeURIComponent(value).replace(
    /[!'()*]/g,
    (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`,
  );
}

/// Each segment encoded, the separators left alone — S3 canonicalises the path per segment, so
/// encoding the whole thing would turn every `/` into `%2F` and change the resource being signed.
function encodeKeyPath(key: string): string {
  return key.split("/").map(uriEncode).join("/");
}

function hex(buffer: ArrayBuffer): string {
  return Array.from(new Uint8Array(buffer)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function sha256Hex(value: string): Promise<string> {
  return hex(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)));
}

async function hmac(key: ArrayBuffer | Uint8Array, value: string): Promise<ArrayBuffer> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    key as BufferSource,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return crypto.subtle.sign("HMAC", cryptoKey, new TextEncoder().encode(value));
}

/// kDate -> kRegion -> kService -> kSigning, the standard four-step derivation. Scoped to one day
/// and one region, which is what makes a leaked signature useless for a different day's requests.
async function signingKey(secret: string, dateStamp: string): Promise<ArrayBuffer> {
  const kDate = await hmac(new TextEncoder().encode(`AWS4${secret}`), dateStamp);
  const kRegion = await hmac(kDate, REGION);
  const kService = await hmac(kRegion, SERVICE);
  return hmac(kService, "aws4_request");
}

/// `20130524T000000Z` and `20130524`, the two formats SigV4 wants from the same instant.
function timestamps(now: Date): { amzDate: string; dateStamp: string } {
  const amzDate = now.toISOString().replace(/[:-]|\.\d{3}/g, "");
  return { amzDate, dateStamp: amzDate.slice(0, 8) };
}

export interface PresignOptions {
  /// DELETE is needed because the app removes objects too (a deleted memory takes its photos
  /// with it); HEAD because the logo cache probes for an object rather than downloading it.
  method?: "GET" | "PUT" | "DELETE" | "HEAD";
  expiresIn: number;
  /// Only meaningful for PUT. Signed as a header so R2 rejects an upload whose type does not match
  /// what was authorised — without it a presigned PUT for a JPEG happily accepts an executable.
  contentType?: string;
  /// Only meaningful for PUT. Signed as a header, which is the only size bound a presigned PUT
  /// can carry: SigV4 query auth has no `content-length-range` condition the way a POST policy
  /// does, so the length has to be known at signing time and committed to in the signature. R2
  /// then rejects any upload whose `Content-Length` differs, because the signature will not match.
  contentLength?: number;
  /// Injectable purely so tests can pin a timestamp; production always uses now.
  now?: Date;
}

/// A presigned URL for one object.
///
/// The bucket sits in the path (`/{bucket}/{key}`) rather than the hostname. R2's S3 endpoint is
/// account-scoped and path-style, unlike S3's virtual-host style, and signing it the other way
/// produces a signature R2 will not match.
export async function presign(
  config: R2Config,
  key: string,
  options: PresignOptions,
): Promise<string> {
  const { method = "GET", expiresIn, contentType, contentLength, now = new Date() } = options;
  if (!Number.isInteger(expiresIn) || expiresIn < 1 || expiresIn > MAX_EXPIRES_IN) {
    throw new Error(`expiresIn must be 1..${MAX_EXPIRES_IN} seconds, got ${expiresIn}`);
  }

  const host = r2Host(config);
  const { amzDate, dateStamp } = timestamps(now);
  const scope = `${dateStamp}/${REGION}/${SERVICE}/aws4_request`;
  const canonicalUri = `/${uriEncode(config.bucket)}/${encodeKeyPath(key)}`;

  // `host` is always signed. A PUT additionally signs content-type and content-length, so the
  // authorisation is for one kind of object at one size, rather than for any bytes at all.
  //
  // Built as pairs and sorted, rather than the hand-written two-case version this replaces: the
  // canonical request requires the headers in lowercase alphabetical order, and with three of
  // them an ordering mistake becomes a signature R2 silently refuses.
  const headers: Array<[string, string]> = [["host", host]];
  if (method === "PUT") {
    if (contentType) headers.push(["content-type", contentType]);
    if (contentLength !== undefined) {
      if (!Number.isInteger(contentLength) || contentLength < 0) {
        throw new Error(`contentLength must be a non-negative integer, got ${contentLength}`);
      }
      headers.push(["content-length", String(contentLength)]);
    }
  }
  headers.sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
  const canonicalHeaders = headers.map(([name, value]) => `${name}:${value}\n`).join("");
  const signedHeaders = headers.map(([name]) => name).join(";");

  // Sorted by key, because the canonical request demands it and R2 re-sorts before verifying.
  const query: Array<[string, string]> = [
    ["X-Amz-Algorithm", ALGORITHM],
    ["X-Amz-Credential", `${config.accessKeyId}/${scope}`],
    ["X-Amz-Date", amzDate],
    ["X-Amz-Expires", String(expiresIn)],
    ["X-Amz-SignedHeaders", signedHeaders],
  ];
  query.sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
  const canonicalQuery = query.map(([k, v]) => `${uriEncode(k)}=${uriEncode(v)}`).join("&");

  // UNSIGNED-PAYLOAD: the body is not known at signing time and never is for a presigned URL.
  const canonicalRequest = [
    method,
    canonicalUri,
    canonicalQuery,
    canonicalHeaders,
    signedHeaders,
    "UNSIGNED-PAYLOAD",
  ].join("\n");

  const stringToSign = [ALGORITHM, amzDate, scope, await sha256Hex(canonicalRequest)].join("\n");
  const signature = hex(await hmac(await signingKey(config.secretAccessKey, dateStamp), stringToSign));

  return `https://${host}${canonicalUri}?${canonicalQuery}&X-Amz-Signature=${signature}`;
}
