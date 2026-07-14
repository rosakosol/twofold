// Twofold — thin Supabase auth wrapper for the website.
//
// Uses the exact same Supabase project as the iOS app (Twofold/Twofold/Services/
// SupabaseConfig.swift) and the exact same "Sign in with Apple" identity — so a user
// who signs in here, buys a web subscription, then opens the app and signs in with the
// same Apple ID lands on the same account row and sees the entitlement RevenueCat just
// granted. Requires the Apple provider to be enabled in the Supabase dashboard (Auth →
// Providers → Apple) with a web "Services ID" — see README "Go-live checklist".

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY } from "/assets/js/config.js";

export const supabase = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);

export async function getSession() {
  const { data, error } = await supabase.auth.getSession();
  if (error) {
    console.warn("[twofold] getSession failed", error);
    return null;
  }
  return data.session;
}

export function onAuthChange(callback) {
  const { data } = supabase.auth.onAuthStateChange((_event, session) => callback(session));
  return () => data.subscription.unsubscribe();
}

export async function signInWithApple(redirectTo) {
  const { error } = await supabase.auth.signInWithOAuth({
    provider: "apple",
    options: { redirectTo: redirectTo || window.location.href.split("?")[0] },
  });
  if (error) throw error;
}

export async function signOut() {
  await supabase.auth.signOut();
}
