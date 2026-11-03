/**
 * Reads that fail loudly, for the console and the account page.
 *
 * Every console page used to destructure `{ data }` and drop `error`, so a failed RPC rendered as
 * no data: "Nobody has been reported" with a green tick on the moderation page, an empty support
 * inbox, $0 of API spend. On a screen an operator trusts to say "nothing needs you", an empty
 * state that might be an outage is worse than an error page. These turn a failed read into a
 * throw, which an error.tsx catches (the console's, inside its chrome, or the account page's) with a retry.
 */

/** The part of a supabase-js result these read: PostgrestError is structurally compatible. */
export interface ReadResult<T> {
  data: T | null;
  error: { message: string; code?: string } | null;
}

export class ConsoleReadError extends Error {
  readonly code: string | undefined;
  constructor(what: string, error: { message: string; code?: string }) {
    super(`Couldn't load ${what}: ${error.message}`);
    this.name = "ConsoleReadError";
    this.code = error.code;
  }
}

/** The data, which may legitimately be null (no row), or a throw if the read failed. */
export function dataOrThrow<T>(result: ReadResult<T>, what: string): T | null {
  if (result.error) throw new ConsoleReadError(what, result.error);
  return result.data;
}

/** A list read: [] for no rows, a throw for a failed read. Never [] for a failure. */
export function listOrThrow<T>(result: ReadResult<T[]>, what: string): T[] {
  return dataOrThrow(result, what) ?? [];
}

/**
 * Whether a failed read means "there is no such thing" rather than "something broke". 22P02 is
 * Postgres refusing a malformed uuid (a mistyped /admin/users/… link), PGRST116 is PostgREST's
 * `.single()` finding no row. Anything else, a 42501 or a network error included, is a failure and
 * must not be shown as a missing record.
 */
export function isNotFoundError(error: unknown): boolean {
  const code = typeof error === "object" && error !== null && "code" in error ? (error as { code?: unknown }).code : undefined;
  return code === "22P02" || code === "PGRST116";
}
