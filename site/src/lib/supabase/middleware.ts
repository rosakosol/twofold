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
  // On the *request*, not the response.
  //
  // `response.headers.set` was the original, and it never worked: Next forwards a header to the
  // app only when it is passed through `NextResponse.next({ request: { headers } })`, which is
  // what builds the `x-middleware-request-*` set that the router rebuilds `req.headers` from.
  // Anything not in that set is dropped, so `headers().get("x-pathname")` in the console layout
  // has always been null and the bookmark-preserving redirect has always fallen back to the
  // section root.
  //
  // Worse than not working: because the forwarded set is built from the *incoming* header names,
  // a client that sent its own `X-Pathname` had it passed through verbatim, and that was the
  // value the layout interpolated into a redirect. Setting it here overwrites anything the caller
  // sent, so the layout now reads the real path and only the real path.
  const forwardedHeaders = new Headers(request.headers);
  forwardedHeaders.set("x-pathname", request.nextUrl.pathname + request.nextUrl.search);

  const forwarded = NextResponse.next({ request: { headers: forwardedHeaders } });
  // The cookies the Supabase client set on `response` above have to come with it — a new
  // NextResponse starts empty, and losing them would silently stop the session refreshing.
  response.cookies.getAll().forEach((cookie) => forwarded.cookies.set(cookie));
  response.headers.forEach((value, key) => {
    if (key.toLowerCase() !== "set-cookie") forwarded.headers.set(key, value);
  });

  return forwarded;
}
