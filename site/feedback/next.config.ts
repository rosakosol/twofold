import type { NextConfig } from "next";
import path from "node:path";

const nextConfig: NextConfig = {
  // This app lives inside a monorepo (site/feedback) alongside a sibling package
  // (site/) that has its own lockfile — without this, Turbopack can't tell which
  // directory is actually the workspace root and warns on every build.
  turbopack: {
    root: path.join(__dirname),
  },
};

export default nextConfig;
