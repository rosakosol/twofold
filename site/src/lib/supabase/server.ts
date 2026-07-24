import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import type { Database } from "@/lib/db/types";

/**
 * Server-side Supabase client — for Server Components, Server Actions, and Route
 * Handlers. Must be created fresh per request (cookies() is request-scoped), so this
 * is a factory, not a singleton like the browser client.
 */
export async function createClient() {
  const cookieStore = await cookies();

  return createServerClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options)
            );
          } catch {
            // Called from a Server Component (not a Server Action/Route Handler) —
            // cookies() is read-only there. Safe to ignore as long as middleware.ts
            // is also refreshing the session, which it is (see middleware.ts).
          }
        },
      },
    }
  );
}
