import { createClient } from "@/lib/supabase/server";

/**
 * Server-side admin check, backed by the `is_feedback_admin()` Postgres function
 * (see supabase/migrations — Phase 1). Returns false (rather than throwing) if the
 * function doesn't exist yet or the call fails for any reason — admin gating should
 * fail closed, never open.
 *
 * The RPC is the single source of truth: it keys off the request JWT's `auth.uid()`
 * (validated by Supabase at the PostgREST boundary) and returns false for anyone not
 * signed in. So there's deliberately no separate `auth.getUser()` here — that was a
 * redundant second network round-trip on a request that already runs through the
 * session-refreshing middleware, and dropping it still fails closed for anon/expired
 * tokens (null uid → RPC returns false).
 */
export async function isFeedbackAdmin(): Promise<boolean> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("is_feedback_admin");
  if (error) {
    console.warn("[feedback] is_feedback_admin check failed", error.message);
    return false;
  }
  return data === true;
}
