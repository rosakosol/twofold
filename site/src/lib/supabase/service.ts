import { createClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/db/types";

/**
 * A service-role client, for the few anonymous forms whose database functions must not be callable
 * with the public key: the waitlist (`join_android_waitlist` hands back an address's email-preferences
 * token), the anonymous rate limiter, and web support requests. While those were granted to `anon`,
 * anyone holding the public key could call them directly and skip this site entirely — reading
 * anybody's unsubscribe token, filling someone else's rate-limit buckets, or flooding the support
 * queue. With the grants revoked, these route handlers are the only way in.
 *
 * Server-only. `SUPABASE_SERVICE_ROLE_KEY` has no `NEXT_PUBLIC_` prefix, so Next never inlines it into
 * a client bundle, and the guard below stops this module being used from the browser by mistake.
 * It bypasses RLS, so use it only for those calls — never for anything that reads a user's data.
 */
export function createServiceClient() {
  if (typeof window !== "undefined") {
    throw new Error("createServiceClient is server-only");
  }
  // Trimmed: a key pasted into the Vercel dashboard easily picks up a trailing newline, and
  // Supabase answers that with "Invalid API key" rather than anything that points at the paste.
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();
  if (!key) throw new Error("SUPABASE_SERVICE_ROLE_KEY is not set");
  return createClient<Database>(process.env.NEXT_PUBLIC_SUPABASE_URL!, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
