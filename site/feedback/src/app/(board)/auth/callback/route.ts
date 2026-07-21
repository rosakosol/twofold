import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";

/**
 * Handles both magic-link and OAuth (Google/Apple) redirects back from Supabase.
 * Supabase appends `?code=...` for the PKCE flow every provider here uses.
 */
export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get("code");
  const next = request.nextUrl.searchParams.get("next") ?? "/feedback";
  const origin = request.nextUrl.origin;

  if (code) {
    const supabase = await createClient();
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) {
      return NextResponse.redirect(`${origin}${next}`);
    }
    console.warn("[feedback] auth callback exchange failed", error.message);
  }

  return NextResponse.redirect(`${origin}/auth/sign-in?error=auth_failed`);
}
