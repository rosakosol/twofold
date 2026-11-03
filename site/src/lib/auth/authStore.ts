import type { SupabaseClient, User } from "@supabase/supabase-js";

export interface AuthState {
  user: User | null;
  isLoading: boolean;
}

export type AuthSource = Pick<SupabaseClient["auth"], "getUser" | "onAuthStateChange">;

/**
 * The signed-in user, read once and shared.
 *
 * `useUser()` used to be plain local state: every component that called it ran its own
 * `auth.getUser()`, a round trip to Supabase Auth, and registered its own `onAuthStateChange`
 * listener. The feedback board renders a VoteButton per request card, so a board of 40 requests
 * cost 40-odd auth calls on load. This store does the lookup and holds the listener once, on the
 * first subscriber, and every component reads the same snapshot.
 */
export function createAuthStore(auth: AuthSource) {
  let state: AuthState = { user: null, isLoading: true };
  const listeners = new Set<() => void>();
  let started = false;

  function set(next: AuthState) {
    state = next;
    for (const listener of listeners) listener();
  }

  function start() {
    started = true;
    auth
      .getUser()
      .then(({ data }) => set({ user: data.user, isLoading: false }))
      .catch(() => set({ user: null, isLoading: false }));
    // Kept for the life of the page: it is one listener, and the next component to mount would
    // only start another.
    auth.onAuthStateChange((_event, session) => set({ user: session?.user ?? null, isLoading: false }));
  }

  return {
    subscribe(listener: () => void) {
      listeners.add(listener);
      if (!started) start();
      return () => {
        listeners.delete(listener);
      };
    },
    getSnapshot: () => state,
  };
}

/** What the server render (and the first client render, before hydration) sees. */
export const SERVER_AUTH_STATE: AuthState = { user: null, isLoading: true };
