import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import type { Database } from "@/lib/db/types";

/**
 * Refreshes the auth session on every request that passes through middleware.ts.
 * This is what keeps a signed-in user's session alive across Server Component
 * navigations without needing a client-side refresh — the standard @supabase/ssr
 * Next.js App Router pattern.
 */
export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({ request });

  const supabase = createServerClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
          response = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options)
          );
        },
      },
    }
  );

  // Required: this actually validates/refreshes the token. Don't remove it even
  // though the result isn't used directly here — getSession() alone doesn't refresh.
  await supabase.auth.getUser();

  // A server component cannot see which URL it is rendering — `headers()` carries what the browser
  // sent, and the path is not in it. The gates need it so that signing in returns somebody to the
  // page they actually asked for rather than to the section's root, which is the difference
  // between a bookmark working and a bookmark nearly working.
  response.headers.set("x-pathname", request.nextUrl.pathname + request.nextUrl.search);

  return response;
}
