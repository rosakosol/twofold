import type { NextConfig } from "next";
import path from "node:path";

const nextConfig: NextConfig = {
  // This app lives inside a larger monorepo (twofold/) alongside unrelated sibling
  // directories (Twofold/ the iOS app, supabase/ the backend) — pinning this explicitly
  // avoids Turbopack scanning upward and guessing wrong about the workspace root.
  turbopack: {
    root: path.join(__dirname),
  },

  // There were none of these at all.
  //
  // The reason it matters here more than on a typical marketing site: `@supabase/ssr` must set
  // its auth cookies `httpOnly: false`, because `createBrowserClient` reads the session out of
  // `document.cookie` for every TanStack hook in `src/lib/queries`. That is inherent to this
  // architecture rather than a mistake — but it means any XSS is full session theft, including an
  // admin's, and a CSP is the cheap thing standing in the way. There is no XSS sink today: zero
  // `dangerouslySetInnerHTML` and zero `innerHTML` in `src/`.
  //
  // `unsafe-inline` for styles because Next injects them, and `unsafe-inline`/`unsafe-eval` for
  // scripts because Next's dev overlay and Sanity Studio both need them. That weakens the script
  // directive considerably and is worth being honest about: the value here is mostly
  // `frame-ancestors`, `object-src` and `base-uri`, which are absolute and which nothing in the
  // app needs. Tightening the script side means a nonce, which is a separate change.
  async headers() {
    return [
      {
        // Everything except the Studio. `/studio` mounts Sanity's own application, which loads
        // its own workers and assets and is not ours to predict — a CSP that breaks the content
        // editor is a worse outcome than one page without a CSP, and nothing user-authored is
        // rendered there anyway. The other three headers still apply to it, below.
        source: "/((?!studio).*)",
        headers: [
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
          // Clickjacking the console is mostly inert — its destructive actions require typing a
          // confirmation string — but this costs nothing and does not rely on that staying true.
          { key: "X-Frame-Options", value: "DENY" },
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
              "script-src 'self' 'unsafe-inline' 'unsafe-eval'",
              // Supabase for auth and data, Sanity for content, RevenueCat for web billing.
              "connect-src 'self' https://*.supabase.co wss://*.supabase.co https://*.sanity.io https://*.revenuecat.com",
            ].join("; "),
          },
        ],
      },
      {
        // The Studio gets everything but the CSP.
        source: "/studio/:path*",
        headers: [
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
          { key: "X-Frame-Options", value: "DENY" },
        ],
      },
    ];
  },
};

export default nextConfig;
