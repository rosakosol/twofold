import type { NextConfig } from "next";
import path from "node:path";

const nextConfig: NextConfig = {
  // Lets this app live at twofoldapp.com.au/feedback/* behind a Cloudflare Pages
  // Function proxy (site/functions/feedback/[[path]].ts) instead of its own separate
  // domain — auto-prefixes every route AND _next/static asset, so one proxy rule
  // handles the whole app. The board's own root page is now what used to be /feedback
  // (see src/app/page.tsx) specifically so this doesn't double up into /feedback/feedback.
  basePath: "/feedback",
  // This app lives inside a monorepo (site/feedback) alongside a sibling package
  // (site/) that has its own lockfile — without this, Turbopack can't tell which
  // directory is actually the workspace root and warns on every build.
  turbopack: {
    root: path.join(__dirname),
  },
};

export default nextConfig;
