// Records every outbound metered third-party call, so the cost of running this app is a number in
// the database rather than something read off a vendor dashboard after somebody thinks to look.
//
// Writes go through `public.record_api_call` rather than straight at the table. `api_usage_events`
// lives in `private`, which `config.toml` does not serve over PostgREST at any privilege level, so
// supabase-js cannot reach it directly — the RPC is a security-definer door granted to
// `service_role` alone. See 20261109000100_api_usage_metering.sql.
//
// ---------------------------------------------------------------------------
// This module must never break a caller
// ---------------------------------------------------------------------------
//
// Metering is bookkeeping about the work, not the work. A flight refresh that succeeded and then
// failed to record itself has still refreshed the flight, and turning that into a thrown error
// would mean an outage in the usage table becomes an outage in flight tracking — trading something
// that matters for something that does not. So every path here swallows, logs, and returns.
//
// The cost of that choice is undercounting during an incident, which is the right way round: an
// estimate that is low and known to be low is recoverable from the provider's own invoice, and the
// console's reconciliation field exists precisely to surface that gap.
//
// ---------------------------------------------------------------------------
// Why the insert is awaited rather than fired and forgotten
// ---------------------------------------------------------------------------
//
// A floating promise in an edge function is not guaranteed to finish — the isolate can be torn
// down the moment the response is returned, which would drop exactly the rows written during the
// busiest ticks. Awaiting costs a few milliseconds against a caller that already sleeps 200ms
// between AeroAPI calls (`INTER_CALL_DELAY_MS` in refresh-due-flights), and at the volumes
// involved — a few hundred calls a day — that is not a cost worth optimising. If this ever becomes
// hot, buffer per invocation and flush in a `finally`; do not switch to fire-and-forget.

// Type-only, so nothing is imported at runtime unless a client is actually needed — see
// `usageClient()` below.
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

/// What the call was about. `calledBy` is the edge function's own name — the thing that separates
/// "the cron is spending this" from "users are", which is the difference between a cadence bug and
/// a product one.
export interface ApiCallContext {
  calledBy: string;
  /// The upstream flight this call concerned. The key field for measuring duplicate fetches: the
  /// main loop in refresh-due-flights is not deduped by fa_flight_id, so two couples tracking one
  /// real-world flight bill two identical calls per tick, and counting rows against distinct
  /// fa_flight_ids is what makes that visible.
  faFlightId?: string | null;
  flightId?: string | null;
  coupleId?: string | null;
  /// How many `flights` rows this single call served. 1 while nothing is deduped. If the main loop
  /// learns to fetch once and apply to many, this becomes that many — one call recorded once,
  /// rather than N invented rows that would make the saving invisible.
  servedFlightCount?: number;
}

export interface ApiCallOutcome {
  provider: string;
  /// The billable class, never the raw path — 'flights/{id}', not '/flights/QF9-abc'.
  endpoint: string;
  /// Null when the request never received one at all (network failure, timeout).
  status: number | null;
  wasRetry: boolean;
  durationMs: number;
}

/// Used when a call site has not been given a context yet. Deliberately a visible placeholder
/// rather than an empty string: a run of these in the console means an unattributed call path,
/// which is a thing to go and fix, not a blank to overlook.
const UNATTRIBUTED = "unattributed";

let cached: SupabaseClient | null | undefined;

/// Null (rather than a throw) when the environment has no service role key — a local `deno test`
/// or a one-off script should not fail because it cannot meter itself.
///
/// supabase-js is imported dynamically, not at the top of the file. This module is pulled in by
/// `aeroapi.ts`, which is pulled in by nearly every flight function, and a static import would make
/// all of them load the client library whether or not they ever record anything. It also keeps the
/// module importable — and therefore testable — somewhere that cannot resolve the dependency.
async function usageClient(): Promise<SupabaseClient | null> {
  if (cached !== undefined) return cached;

  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    console.warn("[api-usage] SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY not set — usage is not being recorded");
    cached = null;
    return cached;
  }

  const { createClient } = await import("jsr:@supabase/supabase-js@2");
  cached = createClient(url, key);
  return cached;
}

/// Shapes the RPC arguments. Pure, and separate from the write so the mapping can be tested
/// without a database — the field names here have to match the SQL function's parameters exactly,
/// and a silent typo would produce rows with null attribution that look like an unattributed call
/// path rather than a bug.
export function usageArgs(outcome: ApiCallOutcome, context?: ApiCallContext): Record<string, unknown> {
  return {
    p_provider: outcome.provider,
    p_endpoint: outcome.endpoint,
    p_called_by: context?.calledBy ?? UNATTRIBUTED,
    p_status: outcome.status,
    p_was_retry: outcome.wasRetry,
    p_duration_ms: outcome.durationMs,
    p_fa_flight_id: context?.faFlightId ?? null,
    p_flight_id: context?.flightId ?? null,
    p_couple_id: context?.coupleId ?? null,
    p_served_flight_count: Math.max(1, context?.servedFlightCount ?? 1),
  };
}

/// Records one call. Never throws, never rejects.
///
/// `client` is injectable for tests only; production callers pass nothing and get the lazily
/// created service-role client.
export async function recordApiCall(
  outcome: ApiCallOutcome,
  context?: ApiCallContext,
  client?: SupabaseClient | null,
): Promise<void> {
  try {
    const supabase = client === undefined ? await usageClient() : client;
    if (!supabase) return;

    const { error } = await supabase.rpc("record_api_call", usageArgs(outcome, context));
    if (error) {
      // Logged, not thrown. No endpoint value is secret, and none of these fields carry a key.
      console.error("[api-usage] could not record call:", error.message);
    }
  } catch (err) {
    console.error("[api-usage] could not record call:", (err as Error).message);
  }
}

/// Test seam: forces the next `usageClient()` to re-read the environment.
export function resetUsageClientForTesting(): void {
  cached = undefined;
}
