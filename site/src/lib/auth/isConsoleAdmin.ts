import { createClient } from "@/lib/supabase/server";

/**
 * Whether the caller holds ANY admin role. Gates entry to the console shell only.
 *
 * The layout used to call `isFeedbackAdmin`, which since the role split means the `content` role
 * specifically — so a billing-only admin, the very separation that split exists to allow, was
 * redirected away from the console before reaching the page they were given a role for.
 *
 * Fails closed, like `isFeedbackAdmin`: any error is a false.
 */
export async function isConsoleAdmin(): Promise<boolean> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("is_console_admin");
  if (error) {
    console.warn("[console] is_console_admin check failed", error.message);
    return false;
  }
  return data === true;
}
