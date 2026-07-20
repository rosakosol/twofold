import { createBrowserClient } from "@supabase/ssr";
import type { Database } from "@/lib/db/types";

/**
 * Browser-side Supabase client — for Client Components and TanStack Query hooks.
 * Safe to call repeatedly; @supabase/ssr manages a single underlying instance per
 * cookie store internally, but we memoize here too to avoid re-creating on every render.
 */
let client: ReturnType<typeof createBrowserClient<Database>> | undefined;

export function createClient() {
  if (client) return client;
  client = createBrowserClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );
  return client;
}
