import { type NextRequest } from "next/server";
import { updateSession } from "@/lib/supabase/middleware";

export async function middleware(request: NextRequest) {
  return updateSession(request);
}

export const config = {
  matcher: [
    /*
     * Only the paths that actually need a session.
     *
     * This used to match everything but static assets, which meant a signed-in visitor paid a
     * session refresh — a round trip to Supabase in Sydney — on every marketing page as well. The
     * homepage, pricing, FAQ, features, terms and privacy are statically rendered and identical
     * for everybody; refreshing a token before serving one bought nothing and was pure latency on
     * the pages people hit first.
     *
     * The routes below are the ones that read the session server-side, plus the auth routes that
     * establish it. A cookie that goes stale while somebody reads the FAQ is refreshed the moment
     * they navigate somewhere that cares, which is the first moment it matters.
     */
    "/account/:path*",
    "/admin/:path*",
    "/feedback/:path*",
    "/studio/:path*",
    "/auth/:path*",
  ],
};
