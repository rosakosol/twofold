"use client";

import { useSyncExternalStore } from "react";
import { createClient } from "@/lib/supabase/client";
import { createAuthStore, SERVER_AUTH_STATE } from "@/lib/auth/authStore";

/** One store per tab, made on first use (see authStore.ts for why it is shared). */
let store: ReturnType<typeof createAuthStore> | null = null;
function authStore() {
  store ??= createAuthStore(createClient().auth);
  return store;
}

function subscribe(listener: () => void) {
  return authStore().subscribe(listener);
}

function getSnapshot() {
  return authStore().getSnapshot();
}

function getServerSnapshot() {
  return SERVER_AUTH_STATE;
}

/** Client-side auth state, pushed by onAuthStateChange. Every caller shares one lookup and one
 *  listener, so it is cheap to call from every card in a list. */
export function useUser() {
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}
