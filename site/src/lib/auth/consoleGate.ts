/**
 * What the console door does with a session, as a pure decision so every case can be tested.
 *
 * The database is the real gate: `is_*_admin()` refuses the data. This only decides what to show a
 * person standing in front of it, so that an admin at aal1 is sent to do their second step rather
 * than looking at a console full of refusals.
 *
 * It works before and after enforcement (supabase/pending/admin_mfa_enforcement.sql) with no code
 * change, because `dataGateOpen` is the data gate's own answer rather than a setting. For an admin at
 * aal1 with no factor it is true today, so they are let in and nagged; once enforcement lands it is
 * false, so they are sent to enrol instead of to pages that cannot load.
 */
export interface ConsoleAccess {
  /** On the admin roster, whatever the session's assurance level. For routing only. */
  isAdmin: boolean;
  aal: string;
  hasVerifiedFactor: boolean;
  /** What `is_console_admin()` says for this session right now. */
  dataGateOpen: boolean;
}

export type ConsoleGate =
  /** Not on the roster, or the check itself failed. */
  | "not-admin"
  | "open"
  /** Let in with a banner: no factor yet, and enforcement is not on. */
  | "open-prompt-enrol"
  | "challenge"
  | "enrol";

export function consoleGate(access: ConsoleAccess | null): ConsoleGate {
  if (!access?.isAdmin) return "not-admin";
  if (access.aal === "aal2") return "open";
  // Before the gate is even asked: someone with a factor always does it, in both stages. Having one
  // and not being asked for it would make it decoration.
  if (access.hasVerifiedFactor) return "challenge";
  return access.dataGateOpen ? "open-prompt-enrol" : "enrol";
}

/** `my_console_access()`'s answer, or null for anything that isn't one, which reads as no access. */
export function parseConsoleAccess(data: unknown): ConsoleAccess | null {
  if (typeof data !== "object" || data === null) return null;
  const row = data as Record<string, unknown>;
  if (typeof row.is_admin !== "boolean" || typeof row.aal !== "string") return null;
  return {
    isAdmin: row.is_admin,
    aal: row.aal,
    hasVerifiedFactor: row.has_verified_factor === true,
    dataGateOpen: row.data_gate_open === true,
  };
}
