import { FunctionsFetchError, FunctionsHttpError } from "@supabase/supabase-js";

/**
 * The reason an edge function refused, rather than a guess at it.
 *
 * `functions.invoke` does not put a non-2xx body in `data` — `data` is null and the Response is
 * parked on `error.context`, unread. Every caller that checked `data?.error` was therefore reading
 * a field that is only ever populated on success, and showing its own fallback for all of them.
 * The console said "Couldn't send that reply. Nothing has changed — try again." whether the real
 * answer was "Not authorised", "Email sending isn't set up", or "That conversation has no address
 * to reply to" — three different problems with three different fixes, none of which is "try again".
 *
 * Reading the body consumes it, so this is called once per failure.
 */
export async function functionErrorMessage(error: unknown, fallback: string): Promise<string> {
  if (error instanceof FunctionsHttpError) {
    try {
      const body = await error.context.json();
      if (typeof body?.error === "string" && body.error.trim()) return body.error;
    } catch {
      // Not JSON — a gateway error page, or a runtime crash before the handler replied.
    }
    return `${fallback} (HTTP ${error.context.status})`;
  }

  // No response at all: the request may or may not have been carried out. Saying "nothing changed"
  // here would be a claim we cannot support, and for a send it is the claim that causes a duplicate.
  if (error instanceof FunctionsFetchError) {
    return "Couldn't reach the server, so this may or may not have gone through. Check before retrying.";
  }

  if (error instanceof Error && error.message) return error.message;
  return fallback;
}
