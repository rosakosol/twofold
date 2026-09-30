"use client";

import { createClient } from "@/lib/supabase/client";

// Thin Apple-sign-in wrapper for the marketing/pricing pages, reusing the app's own
// Supabase browser client (@/lib/supabase/client) rather than a separate one — this is
// the exact same Supabase project and "Sign in with Apple" identity the iOS app uses,
// so a web purchase and the app see the same account row. Distinct sign-in *surface*
// from the feedback board's own sign-in page (src/app/(board)/auth/), but
// the same underlying Supabase project — no conflict, same pattern as the app's real
// Sign in with Apple. Requires the Apple provider enabled in Supabase (Auth ->
// Providers -> Apple) with a web "Services ID".

export async function getSession() {
  const supabase = createClient();
  const { data, error } = await supabase.auth.getSession();
  if (error) {
    console.warn("[twofold] getSession failed", error);
    return null;
  }
  return data.session;
}

export function onAuthChange(callback: (session: import("@supabase/supabase-js").Session | null) => void) {
  const supabase = createClient();
  const {
    data: { subscription },
  } = supabase.auth.onAuthStateChange((_event, session) => callback(session));
  return () => subscription.unsubscribe();
}

/** The two OAuth providers the iOS app signs in with. */
export type OAuthProvider = "apple" | "google";

/**
 * Starts an OAuth redirect. The browser navigates away on success, so nothing returns.
 *
 * `redirectTo` defaults to this page without its query string, which is what makes the pending-plan
 * resume in PricingClient work: the session is established back on /pricing rather than on the
 * board's /auth/callback, and the flow picks up where it left off.
 */
export async function signInWithProvider(provider: OAuthProvider, redirectTo?: string) {
  const supabase = createClient();
  const { error } = await supabase.auth.signInWithOAuth({
    provider,
    options: { redirectTo: redirectTo || window.location.href.split("?")[0] },
  });
  if (error) throw error;
}

/**
 * Creates an account with an email address and a password — the app's third signup method, and the
 * one that made a magic link the wrong choice here.
 *
 * A magic link attaches the purchase perfectly well; the problem is the return trip. The app's
 * sign-in screen offers email *and password*, Apple and Google, with no one-time-link option — so a
 * buyer who signed up by link arrives at the app holding an account with no password and no way in
 * except "Forgot password?", which is a door labelled for somebody who had one. Signing up with a
 * password gives them a credential that works in the app immediately.
 *
 * `first_name` goes into the user metadata because `handle_new_user` (20260708102734) reads exactly
 * that key when it creates the profile row. Without it the account is created nameless and the app
 * greets them as "You" until onboarding fixes it — the complaint 20261106000000 was written about.
 *
 * No email confirmation step stands between this and a session: `enable_confirmations` is off, the
 * same reason the app's own `signUp` can sign somebody straight in. If that is ever turned on, this
 * returns a user with no session and the purchase that follows it will fail.
 */
export async function signUpWithPassword(firstName: string, email: string, password: string) {
  const supabase = createClient();
  const { data, error } = await supabase.auth.signUp({
    email: email.trim(),
    password,
    options: { data: { first_name: firstName.trim() } },
  });
  if (error) throw error;
  return data;
}

/**
 * Signs in an existing email/password account — the returning half, and the reason this page cannot
 * offer Apple and Google alone. Somebody who created their account in onboarding with an email
 * address and then quit at the paywall is among the most likely people to buy here, and for them a
 * provider button is not a login, it is a second account.
 */
export async function signInWithPassword(email: string, password: string) {
  const supabase = createClient();
  const { data, error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
  if (error) throw error;
  return data;
}

/**
 * Whether a failed signup failed because the address already has an account.
 *
 * Two shapes, because Supabase has used both: an explicit error, and — when it is configured to
 * avoid confirming to a stranger which addresses are registered — a success carrying a user with no
 * identities. Reading only the first would leave somebody staring at a form that appeared to work.
 */
export function isExistingAccountError(error: unknown, data?: { user?: { identities?: unknown[] } | null }) {
  if (data?.user && Array.isArray(data.user.identities) && data.user.identities.length === 0) return true;
  const message = error instanceof Error ? error.message.toLowerCase() : "";
  return message.includes("already registered") || message.includes("already exists");
}

export async function signOut() {
  const supabase = createClient();
  await supabase.auth.signOut();
}
