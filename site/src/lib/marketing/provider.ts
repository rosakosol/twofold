import type { Session } from "@supabase/supabase-js";

/**
 * Which provider a Supabase session was actually created with.
 *
 * /pricing used to assume Apple, because that was the only button it offered. But the feedback
 * board, /admin and /pricing all share one Supabase project and therefore one session, so a
 * session signed in with Google or a magic link on the board arrives here intact — and the page
 * told that person to "sign in with the same Apple ID", naming an account they don't have.
 *
 * The iOS app accepts all three (BackendService.signInWithApple, the Google path beside it, and
 * signUp/signInWithPassword), so the honest instruction is whichever one they actually used.
 */
export type AuthProvider = "apple" | "google" | "email" | "unknown";

export function sessionProvider(session: Session | null): AuthProvider {
  // `app_metadata.provider` is the one the current session was established with; `identities`
  // can list several once an account has been linked, so it isn't the right thing to read here.
  const raw = session?.user.app_metadata?.provider;
  if (raw === "apple" || raw === "google" || raw === "email") return raw;
  return "unknown";
}

/** How to name it in a sentence: "sign in with the same {…}". */
export function providerLabel(provider: AuthProvider): string {
  switch (provider) {
    case "apple":
      return "Apple ID";
    case "google":
      return "Google account";
    case "email":
      return "email address";
    default:
      return "account";
  }
}

/** What to show when there's no email on the session to display instead. */
export function providerFallbackName(provider: AuthProvider): string {
  return provider === "unknown" ? "your account" : `your ${providerLabel(provider)}`;
}
