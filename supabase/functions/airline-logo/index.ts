// Serves an airline logo by IATA code, from our own copy in R2.
//
// The app hits this URL directly from `AsyncImage` (see `AirlineLogo.swift`), unauthenticated, and
// that contract has not changed: `?code=QF` in, image bytes out. What changed is where the bytes
// come from.
//
// It used to mirror images.kiwi.com into a *public* Supabase Storage bucket and 302 to that bucket's
// public URL. Two things wrong with it. The bucket was the only public one left, so the whole
// account kept a public surface for the sake of some logos; and every first request for a code
// still depended on an undocumented third-party CDN being up.
//
// Now the logos are scraped into R2 ahead of time (`scripts/scrape-airline-logos.ts`) and served
// from here. Nothing is public: the function reads R2 with a short-lived presigned GET of its own
// and streams the bytes back, so no bucket is exposed and no URL escapes.
//
// kiwi.com remains as a fallback for a code the scrape has not seen — a new airline, or one that
// only turned up in somebody's booking today. That path also writes the logo into R2, so a given
// code depends on the CDN at most once, ever.
//
// No auth (verify_jwt = false in config.toml). These are small public logo images, the same trust
// level as hitting the CDN directly, which is what the app used to do.

import { presign, r2ConfigFromEnv } from "../_shared/r2.ts";

/// Where logos sit in the bucket. Same shape the other kinds use, so one bucket holds everything.
const PREFIX = "airline-logos";

/// A year, immutable. A carrier's logo effectively never changes, and when one does, the answer is
/// to overwrite the object and let the old copy age out rather than to re-fetch on every render.
const CACHE_CONTROL = "public, max-age=31536000, immutable";

/// images.kiwi.com never 404s. An unknown code 303s to `/airlines/64x64/airlines.png`, a generic
/// placeholder, and a real one 303s to its own `64x64` file — so the status tells you nothing and
/// the redirect target tells you everything. Verified: QF lands on QF.png (2,524 bytes), while ZZZ
/// and QQQ both land on airlines.png with byte-identical content.
///
/// Caching that placeholder is worse than having nothing. It is indistinguishable from a real logo
/// once stored, it would be served forever under `immutable`, and it displaces the app's own
/// fallback with a stranger's house icon. The previous version of this cache stored it.
function isGenericPlaceholder(response: Response): boolean {
  try {
    return new URL(response.url).pathname.endsWith("/airlines.png");
  } catch {
    return false;
  }
}

function isValidIataCode(code: string): boolean {
  return /^[A-Za-z0-9]{2,3}$/.test(code);
}

Deno.serve(async (req) => {
  const code = (new URL(req.url).searchParams.get("code") ?? "").toUpperCase();
  if (!isValidIataCode(code)) {
    return Response.json({ error: "Missing or invalid 'code' query param" }, { status: 400 });
  }

  let config;
  try {
    config = r2ConfigFromEnv();
  } catch (error) {
    console.error("[airline-logo]", (error as Error).message);
    return Response.json({ error: "Storage is not configured" }, { status: 500 });
  }

  const key = `${PREFIX}/${code}.png`;

  // The common path: already ours. One presigned GET, streamed straight back.
  const cached = await fetch(await presign(config, key, { expiresIn: 60 }));
  if (cached.ok) {
    return new Response(cached.body, {
      headers: {
        "content-type": cached.headers.get("content-type") ?? "image/png",
        "cache-control": CACHE_CONTROL,
      },
    });
  }

  // A code the scrape has not seen. Fetch it once, keep it, serve it.
  const upstream = await fetch(`https://images.kiwi.com/airlines/64/${code}.png`);
  if (!upstream.ok || isGenericPlaceholder(upstream)) {
    // Nothing stored, so a carrier that gains a logo later is picked up rather than being masked
    // by a cached placeholder for a year.
    return Response.json({ error: "Logo not found" }, { status: 404 });
  }
  const bytes = await upstream.arrayBuffer();
  const contentType = upstream.headers.get("content-type") ?? "image/png";

  const stored = await fetch(
    await presign(config, key, { method: "PUT", expiresIn: 60, contentType }),
    { method: "PUT", body: bytes, headers: { "content-type": contentType } },
  );
  if (!stored.ok) {
    // Storing failed, which is rare and not this caller's problem — serve the bytes anyway and let
    // the next request try again. Logged so a cache that has silently stopped caching is visible
    // here rather than only as steady traffic to a third party.
    console.error(`[airline-logo] could not store ${code}: ${stored.status}`);
  }

  return new Response(bytes, {
    headers: { "content-type": contentType, "cache-control": CACHE_CONTROL },
  });
});
