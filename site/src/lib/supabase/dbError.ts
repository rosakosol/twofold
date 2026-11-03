/**
 * Database writes from the console, checked properly and explained readably.
 *
 * Two gaps this closes:
 *
 * 1. An update or delete that row-level security filters out is not an error to PostgREST. It
 *    answers 2xx, having changed nothing. The console's write policies are `is_feedback_admin()`,
 *    which means the content role only, while any console admin can open the Feedback and Games
 *    pages. So a support-only admin changing a status saw "Saved" and nothing happened. Writes now
 *    ask for an exact count and treat 0 as a refusal.
 *
 * 2. Every catch showed one generic toast, so a duplicate, a check-constraint failure, a refusal
 *    and a full deck all read "Couldn't save". `describeDbError` maps the common codes.
 */

export class NothingChangedError extends Error {
  constructor(what: string) {
    super(`No ${what} was changed.`);
    this.name = "NothingChangedError";
  }
}

/** Throws the database's error, or NothingChangedError when the write touched no rows. Pass the
 *  result of a write made with `{ count: "exact" }`. A null count (not requested) is not checked. */
export function requireChanged(result: { error: unknown; count: number | null }, what: string): void {
  if (result.error) throw result.error;
  if (result.count === 0) throw new NothingChangedError(what);
}

function codeOf(error: unknown): string | undefined {
  if (typeof error !== "object" || error === null || !("code" in error)) return undefined;
  const code = (error as { code?: unknown }).code;
  return typeof code === "string" ? code : undefined;
}

function messageOf(error: unknown): string | undefined {
  if (typeof error !== "object" || error === null || !("message" in error)) return undefined;
  const message = (error as { message?: unknown }).message;
  return typeof message === "string" && message.trim() ? message : undefined;
}

export function describeDbError(error: unknown, fallback: string): string {
  if (error instanceof NothingChangedError) {
    return "Nothing was changed. Editing this needs the content role, or it was deleted in the meantime.";
  }
  switch (codeOf(error)) {
    case "23505":
      return "That already exists. Change it so it isn't a duplicate.";
    case "23514":
      return "One of those values isn't allowed. Check the fields and try again.";
    case "42501":
      return "You don't have permission to do that. It needs the content role.";
    case "P0001":
      // A function's own `raise exception`, written to be read.
      return messageOf(error) ?? fallback;
    default:
      return fallback;
  }
}
