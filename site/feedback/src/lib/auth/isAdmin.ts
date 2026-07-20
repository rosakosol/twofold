import { createClient } from "@/lib/supabase/server";

/**
 * Server-side admin check, backed by the `is_feedback_admin()` Postgres function
 * (see supabase/migrations — Phase 1). Returns false (rather than throwing) if the
 * function doesn't exist yet or the call fails for any reason — admin gating should
 * fail closed, never open.
 */
export async function isFeedbackAdmin(): Promise<boolean> {
  const supabase = await createClient();
  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) return false;

  const { data, error } = await supabase.rpc("is_feedback_admin");
  if (error) {
    console.warn("[feedback] is_feedback_admin check failed", error.message);
    return false;
  }
  return data === true;
}
