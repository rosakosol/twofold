// Does this implementation of SigV4 agree with a real one?
//
// `r2.ts` signs by hand rather than pulling in the AWS SDK, which is the right call for an Edge
// Function cold start and the wrong call to make on trust. So every expectation below is the URL
// botocore produced for the same inputs — a separate implementation by the people who defined the
// format. If the two agree on the canonical request, the credential scope, the HMAC chain and the
// query ordering, the hand-rolled one is right.
//
// Regenerate with (botocore in a venv, clock pinned via botocore.auth.get_current_datetime):
//
//   auth.get_current_datetime = lambda: datetime(2026, 3, 4, 5, 6, 7, tzinfo=timezone.utc)
//   S3SigV4QueryAuth(Credentials(KEY, SECRET), "s3", "auto", expires=N).add_auth(request)
//
// S3SigV4QueryAuth, not the plain SigV4QueryAuth: only the S3 variant signs UNSIGNED-PAYLOAD,
// which is what a presigned URL must use because the body is unknown when it is signed. The
// generic signer hashes an empty body instead, and produces a signature R2 rejects.
//
// The credentials are AWS's own documentation placeholders, not real ones.

import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { MAX_EXPIRES_IN, presign, r2ConfigFromEnv } from "./r2.ts";

const CONFIG = {
  accountId: "abc123def456",
  accessKeyId: "AKIAIOSFODNN7EXAMPLE",
  secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
  bucket: "twofold-content",
};

/// The instant botocore was pinned to when the expectations below were generated. SigV4 folds the
/// date into both the credential scope and the signing key, so the whole comparison rests on this.
const FROZEN = new Date(Date.UTC(2026, 2, 4, 5, 6, 7));

const cases = [
  {
    name: "GET memory-photos/abc/def/ghi.jpg",
    method: "GET" as const,
    key: "memory-photos/abc/def/ghi.jpg",
    expiresIn: 3600,
    contentType: undefined,
    expected:
      "https://abc123def456.r2.cloudflarestorage.com/twofold-content/memory-photos/abc/def/ghi.jpg?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20260304%2Fauto%2Fs3%2Faws4_request&X-Amz-Date=20260304T050607Z&X-Amz-Expires=3600&X-Amz-SignedHeaders=host&X-Amz-Signature=23a1f5cb109ea3c9fe961931cce68047b055c0f41e6c5d1d521c06993b828c98",
  },
  {
    name: "GET avatars/11111111-2222-3333-4444-555555555555/avatar.jpg",
    method: "GET" as const,
    key: "avatars/11111111-2222-3333-4444-555555555555/avatar.jpg",
    expiresIn: 900,
    contentType: undefined,
    expected:
      "https://abc123def456.r2.cloudflarestorage.com/twofold-content/avatars/11111111-2222-3333-4444-555555555555/avatar.jpg?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20260304%2Fauto%2Fs3%2Faws4_request&X-Amz-Date=20260304T050607Z&X-Amz-Expires=900&X-Amz-SignedHeaders=host&X-Amz-Signature=2bf7b5d2b948663a68b1b835a62e9bb8bf1d574adce0a1f698dfb698a336b6d7",
  },
  {
    name: "PUT memory-photos/abc/def/new.jpg",
    method: "PUT" as const,
    key: "memory-photos/abc/def/new.jpg",
    expiresIn: 300,
    contentType: "image/jpeg",
    expected:
      "https://abc123def456.r2.cloudflarestorage.com/twofold-content/memory-photos/abc/def/new.jpg?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20260304%2Fauto%2Fs3%2Faws4_request&X-Amz-Date=20260304T050607Z&X-Amz-Expires=300&X-Amz-SignedHeaders=content-type%3Bhost&X-Amz-Signature=eabf029ad4fb326d9f3ef2a06b882167e7c8e9fb2e0cf0804060172ffd0c8d02",
  },
  {
    name: "GET airline-logos/QF.png",
    method: "GET" as const,
    key: "airline-logos/QF.png",
    expiresIn: 86400,
    contentType: undefined,
    expected:
      "https://abc123def456.r2.cloudflarestorage.com/twofold-content/airline-logos/QF.png?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20260304%2Fauto%2Fs3%2Faws4_request&X-Amz-Date=20260304T050607Z&X-Amz-Expires=86400&X-Amz-SignedHeaders=host&X-Amz-Signature=97d1dd7b4c034e308c004501a627bc5bb24d6d40abd7f12d0c5e87e043b72011",
  },
];

for (const c of cases) {
  Deno.test(`presign matches botocore: ${c.name}`, async () => {
    const url = await presign(CONFIG, c.key, {
      method: c.method,
      expiresIn: c.expiresIn,
      contentType: c.contentType,
      now: FROZEN,
    });
    assertEquals(url, c.expected);
  });
}

/// Percent-encoding is the half botocore cannot check here, because its own URL rendering leaves
/// the path as it was handed in. SigV4 requires RFC 3986, which is stricter than
/// encodeURIComponent: `!'()*` must be escaped too, and a key containing an apostrophe would
/// otherwise sign here and 403 at R2.
Deno.test("keys are RFC 3986 encoded, separators left alone", async () => {
  const url = await presign(CONFIG, "flight-documents/a b/c'd(e)/f*g.pdf", {
    expiresIn: 3600,
    now: FROZEN,
  });
  const path = new URL(url).pathname;
  assertEquals(path, "/twofold-content/flight-documents/a%20b/c%27d%28e%29/f%2Ag.pdf");
});

/// Signed as a header, so R2 refuses an upload whose type does not match what was authorised.
Deno.test("a PUT with a content type signs it, a GET does not", async () => {
  const put = await presign(CONFIG, "x.jpg", {
    method: "PUT",
    expiresIn: 300,
    contentType: "image/jpeg",
    now: FROZEN,
  });
  assertEquals(new URL(put).searchParams.get("X-Amz-SignedHeaders"), "content-type;host");

  const get = await presign(CONFIG, "x.jpg", { expiresIn: 300, contentType: "image/jpeg", now: FROZEN });
  assertEquals(new URL(get).searchParams.get("X-Amz-SignedHeaders"), "host");
});

/// A silently-clamped expiry would hand out URLs that outlive what the caller asked for.
Deno.test("an out-of-range expiry is refused rather than clamped", async () => {
  await assertRejects(() => presign(CONFIG, "x.jpg", { expiresIn: 0 }), Error, "expiresIn");
  await assertRejects(
    () => presign(CONFIG, "x.jpg", { expiresIn: MAX_EXPIRES_IN + 1 }),
    Error,
    "expiresIn",
  );
});

/// Half-configured is worse than unconfigured: it presigns happily and fails at R2 with a 403 that
/// says nothing about which secret was missing.
Deno.test("missing configuration names what is missing", () => {
  const env = (key: string) => (key === "R2_BUCKET" ? undefined : "value");
  try {
    r2ConfigFromEnv(env);
    throw new Error("expected a throw");
  } catch (error) {
    assertEquals((error as Error).message.includes("R2_BUCKET"), true);
  }
});
