import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { BASE_PATH } from "@/lib/basePath";

/**
 * Handles both magic-link and OAuth (Google) redirects back from Supabase. Supabase
 * appends `?code=...` for the PKCE flow both providers use here.
 *
 * Builds the redirect target explicitly from X-Forwarded-Host/Proto (set by the
 * Cloudflare Pages Function that proxies twofoldapp.com.au/feedback/* to this app —
 * see site/functions/feedback/[[path]].ts) rather than trusting this request's own
 * origin: once requests arrive via that proxy, the app's own URL reflects the Vercel
 * deployment's host, not the public-facing twofoldapp.com.au one the browser and its
 * session cookie actually need to land on. Falls back to the app's own origin when
 * there's no proxy in front (local dev, or hitting the Vercel URL directly).
 */
export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get("code");
  const next = request.nextUrl.searchParams.get("next") ?? "/";

  const forwardedHost = request.headers.get("x-forwarded-host");
  const forwardedProto = request.headers.get("x-forwarded-proto") ?? "https";
  const origin = forwardedHost ? `${forwardedProto}://${forwardedHost}` : request.nextUrl.origin;

  if (code) {
    const supabase = await createClient();
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) {
      return NextResponse.redirect(`${origin}${BASE_PATH}${next}`);
    }
    console.warn("[feedback] auth callback exchange failed", error.message);
  }

  return NextResponse.redirect(`${origin}${BASE_PATH}/auth/sign-in?error=auth_failed`);
}
