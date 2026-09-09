import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";

/**
 * Handles both magic-link and OAuth (Google/Apple) redirects back from Supabase.
 * Supabase appends `?code=...` for the PKCE flow every provider here uses.
 *
 * Both failure paths carry the reason forward. They used to collapse into a bare
 * `error=auth_failed`, which the sign-in page then ignored entirely — so a failed
 * sign-in looked identical to never having pressed the button, with the only clue
 * a server log line that existed for just one of the two branches.
 */
export async function GET(request: NextRequest) {
  const params = request.nextUrl.searchParams;
  const code = params.get("code");
  const origin = request.nextUrl.origin;

  // `next` arrives from the query string, so it is caller-controlled. Only a single-slash
  // relative path is honoured: "//evil.com" and "https://evil.com" are protocol-relative and
  // absolute respectively, and either would send a freshly-signed-in user off-site the moment
  // this is ever built with `new URL(next, origin)` instead of concatenation.
  const requestedNext = params.get("next");
  const next =
    requestedNext && /^\/(?!\/)/.test(requestedNext) ? requestedNext : "/feedback";

  function failed(reason: string) {
    console.warn("[feedback] auth callback failed", reason);
    const url = new URL("/auth/sign-in", origin);
    url.searchParams.set("error", "auth_failed");
    url.searchParams.set("reason", reason);
    return NextResponse.redirect(url);
  }

  // No code means Supabase bounced us here with its own error instead: the provider is
  // misconfigured, consent was denied, or the signup trigger raised. The description is
  // the only place that distinction survives.
  if (!code) {
    return failed(
      params.get("error_description") ?? params.get("error") ?? "no code in callback"
    );
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.exchangeCodeForSession(code);
  if (error) {
    // Overwhelmingly this is a missing PKCE code verifier, which means the cookie was set
    // on a different origin than the one this request arrived on. The sign-in page always
    // points the callback at its own origin, so if this fires, Supabase substituted its
    // Site URL because this origin is absent from the project's Redirect URLs.
    return failed(error.message);
  }

  return NextResponse.redirect(`${origin}${next}`);
}
