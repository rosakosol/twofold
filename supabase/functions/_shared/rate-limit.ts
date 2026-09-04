// Per-user rate limiting for Edge Functions that spend money on an outbound third-party call.
//
// The check lives in Postgres (`consume_rate_limit`, 20260918000000) rather than in the isolate,
// because an Edge Function isolate is per-request and shares no memory with the next one — an
// in-process counter would reset on every cold start and count nothing. The database is the only
// state these functions have in common.
//
// The client passed in MUST be the user-scoped one (built with the caller's own Authorization
// header), not a service-role client. `consume_rate_limit` derives the caller from `auth.uid()`
// and refuses when it is null, so a service-role client would fail every call — which is the safe
// direction to fail, but it would fail loudly and permanently rather than subtly.

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

export interface RateLimit {
  /// Names what is being limited. One bucket per endpoint: buckets do not share a budget, so a
  /// person who has used up their support emails can still parse a flight email.
  bucket: string;
  /// Calls admitted per window.
  limit: number;
  /// A Postgres interval literal, e.g. "1 hour". Must be positive and at most 1 day.
  window: string;
}

/// Records this call and returns a ready-to-send 429 if it is over the limit, or null to proceed.
///
/// Returning the Response rather than throwing keeps the call site a single `if` and means the
/// wording, the status and the `Retry-After` header are decided in one place across every caller.
///
/// Fails OPEN — a database error here returns null and the request proceeds. Deliberate: this
/// limiter guards against a user in a loop, not against an attacker who can also take the database
/// down, and failing closed would turn any transient Postgres blip into a total outage of the
/// feature. The error is logged so a limiter that has silently stopped limiting is visible in the
/// function logs rather than only in the next invoice.
export async function enforceRateLimit(
  client: SupabaseClient,
  { bucket, limit, window }: RateLimit,
): Promise<Response | null> {
  const { data, error } = await client
    .rpc("consume_rate_limit", { p_bucket: bucket, p_limit: limit, p_window: window })
    .single();

  if (error) {
    console.error(`[rate-limit] ${bucket}: check failed, allowing request:`, error.message);
    return null;
  }

  const result = data as { allowed: boolean; retry_after_seconds: number } | null;
  if (!result || result.allowed) return null;

  // Deliberately says nothing about the limit, the window, how much of it is left, or who the
  // caller is — the number would only tell someone probing us exactly how to pace themselves, and
  // it is not information a real user can act on. `Retry-After` carries the one fact that is
  // actually useful, in the header where clients already look for it.
  return Response.json(
    { error: "You've done that a few too many times just now — please try again a bit later." },
    { status: 429, headers: { "Retry-After": String(result.retry_after_seconds) } },
  );
}
