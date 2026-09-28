"use client";

import { createClient } from "@/lib/supabase/client";

// Thin Apple-sign-in wrapper for the marketing/pricing pages, reusing the app's own
// Supabase browser client (@/lib/supabase/client) rather than a separate one — this is
// the exact same Supabase project and "Sign in with Apple" identity the iOS app uses,
// so a web purchase and the app see the same account row. Distinct sign-in *surface*
// from the feedback board's own magic-link/Google auth (src/app/(board)/auth/), but
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
 * Emails a sign-in link, for the app's third sign-in method — `signUp`/`signInWithPassword` in
 * BackendService.swift. There is no password field here on purpose: a password set in the app is
 * the same credential, but asking for it on a marketing page is the shape of a phishing form, and
 * a link to the address on the account reaches the same Supabase user either way.
 */
export async function sendMagicLink(email: string, redirectTo?: string) {
  const supabase = createClient();
  const { error } = await supabase.auth.signInWithOtp({
    email,
    options: { emailRedirectTo: redirectTo || window.location.href.split("?")[0] },
  });
  if (error) throw error;
}

export async function signOut() {
  const supabase = createClient();
  await supabase.auth.signOut();
}
