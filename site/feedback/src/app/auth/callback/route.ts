import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

/**
 * Handles both magic-link and OAuth (Google) redirects back from Supabase. Supabase
 * appends `?code=...` for the PKCE flow both providers use here.
 */
export async function GET(request: Request) {
  const { searchParams, origin } = new URL(request.url);
  const code = searchParams.get("code");
  const next = searchParams.get("next") ?? "/feedback";

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
