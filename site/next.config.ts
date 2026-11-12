import type { NextConfig } from "next";
import path from "node:path";
import { STUDIO_URL } from "./src/lib/studio";

const nextConfig: NextConfig = {
  // This app lives inside a larger monorepo (twofold/) alongside unrelated sibling
  // directories (Twofold/ the iOS app, supabase/ the backend) — pinning this explicitly
  // avoids Turbopack scanning upward and guessing wrong about the workspace root.
  turbopack: {
    root: path.join(__dirname),
  },

  // 75 is the default for every image. 90 is for the home page's Memories map, a crop of a phone
  // capture shown larger than on a phone, where 75 left the street labels soft.
  images: {
    qualities: [75, 90],
  },

  // There were none of these at all.
  //
  // The reason it matters here more than on a typical marketing site: `@supabase/ssr` must set
  // its auth cookies `httpOnly: false`, because `createBrowserClient` reads the session out of
  // `document.cookie` for every TanStack hook in `src/lib/queries`. That is inherent to this
  // architecture rather than a mistake — but it means any XSS is full session theft, including an
  // admin's, and a CSP is the cheap thing standing in the way. There is no XSS sink today: zero
  // `innerHTML` in `src/`, and one `dangerouslySetInnerHTML`, the light/dark script in
  // app/layout.tsx, which is a constant string with no input in it. It is inline, so tightening
  // the script directive below to a nonce or hash has to cover it.
  //
  // `unsafe-inline` for styles because Next injects them, and `unsafe-inline`/`unsafe-eval` for
  // scripts because Next's dev overlay and static pages need them (a static page cannot carry a
  // per-request nonce). That weakens the script
  // directive considerably and is worth being honest about: the value here is mostly
  // `frame-ancestors`, `object-src` and `base-uri`, which are absolute and which nothing in the
  // app needs. The console, where it matters most, does not use this one: src/proxy.ts gives
  // /admin a strict per-request CSP with a nonce (lib/security/consoleCsp.ts).
  // Studio is on Sanity's hosting now (src/lib/studio.ts). Old bookmarks land there.
  async redirects() {
    return [
      { source: "/studio", destination: STUDIO_URL, permanent: false },
      { source: "/studio/:path*", destination: STUDIO_URL, permanent: false },
    ];
  },

  async headers() {
    // HSTS is also Vercel's default, but stated here so it does not depend on the host. No
    // includeSubDomains: the mail records live on subdomains nobody has checked serve https.
    const common = [
      { key: "X-Content-Type-Options", value: "nosniff" },
      { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
      // Clickjacking the console is mostly inert — its destructive actions need a typed
      // confirmation and a fresh authenticator code — but this costs nothing and does not rely on that.
      { key: "X-Frame-Options", value: "DENY" },
      { key: "Strict-Transport-Security", value: "max-age=63072000" },
    ];
    return [
      {
        // Everything except the console, whose stricter CSP comes from src/proxy.ts: two policies
        // would both be enforced, and this one adds nothing there. The other headers still apply
        // to it, below.
        source: "/((?!admin).*)",
        headers: [
          ...common,
          {
            key: "Content-Security-Policy",
            value: [
              "default-src 'self'",
              "base-uri 'self'",
              "object-src 'none'",
              "frame-ancestors 'none'",
              "form-action 'self'",
              "img-src 'self' data: blob: https:",
              "font-src 'self' data: https://fonts.gstatic.com",
              "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
              // js.stripe.com: RevenueCat Billing's checkout is Stripe Elements underneath, and
              // Stripe requires its script be loaded from its own origin rather than bundled.
              "script-src 'self' 'unsafe-inline' 'unsafe-eval' https://js.stripe.com",
              // The checkout renders in an iframe. Without this the directive falls back to
              // `default-src 'self'` and the frame is refused — which looks, from the page, like
              // RevenueCat declining to start the purchase rather than like a CSP problem.
              "frame-src 'self' https://js.stripe.com https://hooks.stripe.com https://*.revenuecat.com https://*.revenue.cat",
              // Supabase for auth and data, Sanity for content (only server-side now that Studio
              // is hosted by Sanity, but harmless), RevenueCat and Stripe for billing.
              //
              // RevenueCat is TWO domains, and that is what broke checkout: the SDK calls
              // `api.revenuecat.com` but sends telemetry to `e.revenue.cat`, which `*.revenuecat.com`
              // does not match. A blocked request there is not a blocked analytics ping — the SDK
              // treats it as a failure and reports "Purchase not started due to an error (error code:
              // 0)", which names neither the domain nor the policy.
              "connect-src 'self' https://*.supabase.co wss://*.supabase.co https://*.sanity.io https://*.revenuecat.com https://*.revenue.cat https://api.stripe.com",
            ].join("; "),
          },
        ],
      },
      {
        // The console gets everything but this CSP.
        source: "/admin/:path*",
        headers: common,
      },
    ];
  },
};

export default nextConfig;
