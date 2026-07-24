import type { NextConfig } from "next";
import path from "node:path";

const nextConfig: NextConfig = {
  // This app lives inside a larger monorepo (twofold/) alongside unrelated sibling
  // directories (Twofold/ the iOS app, supabase/ the backend) — pinning this explicitly
  // avoids Turbopack scanning upward and guessing wrong about the workspace root.
  turbopack: {
    root: path.join(__dirname),
  },
};

export default nextConfig;
