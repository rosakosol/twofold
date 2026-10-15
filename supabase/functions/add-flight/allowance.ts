// Whether a newly added flight may be tracked, from what `flight_allowance` returned.
//
// Split out of index.ts so it can be tested at all: that module calls `Deno.serve` at import time.
//
// This used to be inline as `monthlyLimit <= 0 || usedBefore < monthlyLimit`, i.e. a limit of zero
// meant unlimited. Nothing on the server means that. `flight_limit_for_tier` never returns zero, and
// a zero in `private.flight_limit_overrides` is documented (20261018000000) as the way to freeze an
// account's tracking outright — which `enable_flight_tracking` honours (`used >= 0` refuses) and this
// turned into unlimited tracking at ~85c a flight. It also failed open: the RPC's error was never
// read, a failed call left `allowance` null, the limit read as 0, and every add was tracked.
//
// So a missing or unreadable allowance is not a licence. The caller refuses the request on an RPC
// error (the same 503 the subscription check gives); this function is the second line, and treats
// anything it cannot read as a limit as no room.
export interface FlightAllowance {
  limit?: unknown;
  used?: unknown;
}

export function isWithinAllowance(allowance: FlightAllowance | null | undefined): boolean {
  if (!allowance) return false;
  const limit = typeof allowance.limit === "number" ? allowance.limit : Number.NaN;
  const used = typeof allowance.used === "number" ? allowance.used : Number.NaN;
  if (!Number.isFinite(limit) || !Number.isFinite(used)) return false;
  return used < limit;
}
