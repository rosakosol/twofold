import { cache } from "react";
import { createClient } from "@/lib/supabase/server";
import { parseConsoleAccess, type ConsoleAccess } from "@/lib/auth/consoleGate";

/**
 * Where the caller stands at the console door, asked once per request. Gates the console shell and
 * the MFA pages only; the pages inside still check the role they need.
 *
 * Fails closed: any error is null, which `consoleGate` reads as no access.
 */
export const getConsoleAccess = cache(async (): Promise<ConsoleAccess | null> => {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("my_console_access");
  if (error) {
    console.warn("[console] my_console_access check failed", error.message);
    return null;
  }
  return parseConsoleAccess(data);
});
