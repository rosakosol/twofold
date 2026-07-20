// Caching proxy in front of the public logo CDN (images.kiwi.com) — `AirlineLogo.swift` in the
// app used to point straight at that CDN on every single load, no persistence layer of our own,
// so the same "QF"/"SQ"/etc. logo got re-fetched from a third party over and over. The first
// request for a given IATA code here fetches from the CDN and mirrors it into our own
// `airline-logos` Storage bucket, then redirects to that now-cached public URL; every later
// request for the same code is served straight from Supabase's own CDN-backed Storage — no
// origin round-trip, and no longer dependent on images.kiwi.com's own uptime for a logo we've
// already seen once.
//
// No auth required (see config.toml: verify_jwt = false) — `AsyncImage` in the app hits this
// URL directly with a plain GET, the same trust level hitting the CDN directly already had
// (small, non-sensitive public logo images only).

import { createClient } from "jsr:@supabase/supabase-js@2";

const BUCKET = "airline-logos";

function isValidIataCode(code: string): boolean {
  return /^[A-Za-z0-9]{2,3}$/.test(code);
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const code = (url.searchParams.get("code") ?? "").toUpperCase();

  if (!isValidIataCode(code)) {
    return Response.json({ error: "Missing or invalid 'code' query param" }, { status: 400 });
  }

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const path = `${code}.png`;
  const { data: publicUrlData } = serviceClient.storage.from(BUCKET).getPublicUrl(path);

  // Fast path: already cached from a previous request — a lightweight existence probe (list
  // with a search prefix) rather than downloading the object just to confirm it's there.
  const { data: existing } = await serviceClient.storage.from(BUCKET).list("", { search: path });
  if (existing?.some((entry) => entry.name === path)) {
    return Response.redirect(publicUrlData.publicUrl, 302);
  }

  // Miss: fetch from the CDN, mirror into Storage, then redirect to the now-cached copy so this
  // exact code never has to hit the CDN again.
  const cdnResponse = await fetch(`https://images.kiwi.com/airlines/64/${code}.png`);
  if (!cdnResponse.ok) {
    return Response.json({ error: "Logo not found" }, { status: 404 });
  }
  const bytes = await cdnResponse.arrayBuffer();
  const contentType = cdnResponse.headers.get("content-type") ?? "image/png";

  const { error: uploadError } = await serviceClient.storage.from(BUCKET).upload(path, bytes, {
    contentType,
    upsert: true,
  });
  if (uploadError) {
    // Mirroring into Storage failed (rare) — still serve the bytes this one time rather than
    // erroring the caller out; the next request will just retry the cache write.
    console.error(`[airline-logo] upload failed for ${code}:`, uploadError.message);
    return new Response(bytes, { headers: { "content-type": contentType } });
  }

  return Response.redirect(publicUrlData.publicUrl, 302);
});
