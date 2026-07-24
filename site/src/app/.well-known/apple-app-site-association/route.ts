import { NextResponse } from "next/server";

// Lets iOS open Universal Links (https://www.twofoldapp.com.au/invite/CODE) directly in
// Twofold instead of Safari — see Twofold/Twofold/Features/Onboarding/InviteCode.swift and the
// com.apple.developer.associated-domains entitlement (applinks:www.twofoldapp.com.au) in
// Twofold.entitlements. Ported from the old Cloudflare Pages site's
// site/.well-known/apple-app-site-association, which no longer serves production traffic now
// that the marketing site lives here — without this file existing *on this app*, invite links
// silently stopped opening the app and just landed on the plain web page instead.
//
// A route handler (not a static file under public/.well-known/) so the response is guaranteed
// `Content-Type: application/json` regardless of hosting-platform static-file defaults for an
// extensionless file — Apple's own CDN fetches this over HTTPS and is picky about that.
//
// Add a new `{ "/": "..." }` pattern here (inside the same `components` array) for any future
// path that should open the app directly — e.g. if password-reset ever moves from its current
// custom-scheme redirect (twofold://reset-password) to a Universal Link instead.
export async function GET() {
  return NextResponse.json({
    applinks: {
      details: [
        {
          appIDs: ["74FZ8H3GX2.com.orangefinch.Twofold"],
          components: [{ "/": "/invite/*" }],
        },
      ],
    },
  });
}
