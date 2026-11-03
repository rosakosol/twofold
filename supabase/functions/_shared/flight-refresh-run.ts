// The body of the `refresh-due-flights` cron, kept out of its index.ts so tests can import it:
// that file's top-level `Deno.serve` starts a server on import. The cadence it applies is
// documented at the top of refresh-due-flights/index.ts and lives in flight-schedule.ts.

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { AeroApiError } from "./aeroapi.ts";
import {
  type FlightRow,
  loadTrackedFlights,
  maybeRefreshWeather,
  reconcileOverdueArrival,
  refreshOneFlight,
  syncLivePositions,
} from "./flight-sync.ts";
import { notifyArrivalReminder, notifyPreDeparture } from "./notify.ts";
import { describePushTally, type PushTally } from "./apns.ts";
import {
  ARRIVAL_REMINDER_1H_WINDOW_MS,
  ARRIVAL_REMINDER_30M_WINDOW_MS,
  bestKnownArrival,
  dueFlightsInOrder,
  isDueForArrivalReminder,
  isDueForPreDepartureReminder,
  shouldResetArrivalReminder,
} from "./flight-schedule.ts";

const TERMINAL_STATUSES = ["arrived", "landed", "cancelled", "diverted"];

// Spacing between flights, so a run never bursts AeroAPI faster than about five calls a second.
const INTER_CALL_DELAY_MS = 200;

// How long a run keeps starting AeroAPI refreshes, and when its live-position pass stops. Both
// inside the one-minute cron interval, so a run is normally done before the next one starts; the
// lease below only matters when one isn't.
const REFRESH_BUDGET_MS = 40_000;
const RUN_DEADLINE_MS = 50_000;

// A cap on AeroAPI flight lookups per run, whatever the clock says: what one minute may spend.
// At 200 ms apart a run reaches about this many inside REFRESH_BUDGET_MS anyway.
const MAX_REFRESHES_PER_RUN = 150;

// The run lease (20261118000100). Long enough to outlast any run, so a slow run is never joined by
// the next; short enough that a run killed without releasing it holds up flight tracking for a
// few minutes at most.
const LEASE_JOB = "refresh-due-flights";
const LEASE_TTL_SECONDS = 3 * 60;

// Marks a reminder as sent before sending it, and only if it hadn't been (DB-5). Two senders
// holding the same read both used to see "not sent", send, and only then mark it. Whoever's
// update matches the unsent row sends; the other finds nothing to claim.
async function claimReminder(
  serviceClient: SupabaseClient,
  flightId: string,
  flag: "pre_departure_notified" | "arrival_1h_notified" | "arrival_30m_notified",
  patch: Record<string, unknown>,
): Promise<boolean> {
  const { data, error } = await serviceClient
    .from("flights")
    .update({ [flag]: true, ...patch })
    .eq("id", flightId)
    .eq(flag, false)
    .select("id");
  if (error) {
    console.error(`[refresh-due-flights] failed to claim ${flag} for ${flightId}:`, error.message);
    return false;
  }
  return (data?.length ?? 0) > 0;
}

// A send that threw gives its claim back, so the next tick retries — same reasoning as
// everything else in this loop being best-effort per flight.
//
// So does one that reached nobody. sendAPNs reports rather than throws, so before its result was
// read, a reminder sent while Apple answered 503 was marked sent and never went out. "Nobody" is
// the line on purpose: if one phone got it, a retry would tell that phone twice. And only for a
// failure that can pass (429, 5xx, no response): a retired token or a rejected payload will fail
// the same way next tick. The retry comes with the flight's next refresh, and this changes no
// cadence: within ten minutes of departure that's the 1-minute tier, so a pre-departure reminder
// is retried a minute later. An arrival reminder for a flight in cruise waits for the 12-minute
// active tier, so a "Landing in 1 hour" retried after an outage can arrive up to 12 minutes late.
// That's still better than never.
function reachedNobodyForNow(tally: PushTally): boolean {
  return tally.sent === 0 && tally.retryable > 0;
}

async function releaseReminder(
  serviceClient: SupabaseClient,
  flightId: string,
  flag: "pre_departure_notified" | "arrival_1h_notified" | "arrival_30m_notified",
  patch: Record<string, unknown>,
): Promise<void> {
  const { error } = await serviceClient.from("flights").update({ [flag]: false, ...patch }).eq("id", flightId);
  if (error) console.error(`[refresh-due-flights] failed to release ${flag} for ${flightId}:`, error.message);
}

export async function maybeSendArrivalReminders(serviceClient: SupabaseClient, updated: FlightRow, now: number): Promise<void> {
  const currentArrival = bestKnownArrival(updated);

  let arrival1hNotified = updated.arrival_1h_notified;
  let arrival30mNotified = updated.arrival_30m_notified;

  // The arrival moved enough since a reminder went out that it should go out again at the new
  // time. Re-armed only from the time this caller read, so a second sender with the same read
  // can't re-arm a reminder the first has just re-sent.
  for (const window of ["1h", "30m"] as const) {
    const flag = window === "1h" ? "arrival_1h_notified" : "arrival_30m_notified";
    const notifiedFor = window === "1h" ? updated.arrival_1h_notified_for : updated.arrival_30m_notified_for;
    const notified = window === "1h" ? arrival1hNotified : arrival30mNotified;
    if (!notified || !notifiedFor || !shouldResetArrivalReminder(notifiedFor, currentArrival)) continue;
    const { error } = await serviceClient
      .from("flights")
      .update({ [flag]: false, [`${flag}_for`]: null })
      .eq("id", updated.id)
      .eq(`${flag}_for`, notifiedFor);
    if (error) {
      console.error(`[refresh-due-flights] failed to reset ${flag} for ${updated.id}:`, error.message);
      continue;
    }
    if (window === "1h") arrival1hNotified = false;
    else arrival30mNotified = false;
  }

  for (const window of ["1h", "30m"] as const) {
    const windowMs = window === "1h" ? ARRIVAL_REMINDER_1H_WINDOW_MS : ARRIVAL_REMINDER_30M_WINDOW_MS;
    const flag = window === "1h" ? "arrival_1h_notified" : "arrival_30m_notified";
    const notified = window === "1h" ? arrival1hNotified : arrival30mNotified;
    if (!isDueForArrivalReminder(updated, now, windowMs, notified)) continue;
    if (!(await claimReminder(serviceClient, updated.id, flag, { [`${flag}_for`]: currentArrival }))) continue;
    try {
      const tally = await notifyArrivalReminder(serviceClient, updated.id, window);
      if (reachedNobodyForNow(tally)) {
        console.warn(`[refresh-due-flights] ${window} arrival reminder for ${updated.id} reached nobody (${describePushTally(tally)}); retrying next tick`);
        await releaseReminder(serviceClient, updated.id, flag, { [`${flag}_for`]: null });
      }
    } catch (err) {
      console.error(`[refresh-due-flights] ${window} arrival reminder failed for ${updated.id}:`, (err as Error).message);
      await releaseReminder(serviceClient, updated.id, flag, { [`${flag}_for`]: null });
    }
  }
}

export async function maybeSendPreDepartureReminder(serviceClient: SupabaseClient, updated: FlightRow, now: number): Promise<void> {
  if (!isDueForPreDepartureReminder(updated, now)) return;
  if (!(await claimReminder(serviceClient, updated.id, "pre_departure_notified", {}))) return;
  try {
    const tally = await notifyPreDeparture(serviceClient, updated.id);
    if (reachedNobodyForNow(tally)) {
      console.warn(`[refresh-due-flights] pre-departure reminder for ${updated.id} reached nobody (${describePushTally(tally)}); retrying next tick`);
      await releaseReminder(serviceClient, updated.id, "pre_departure_notified", {});
    }
  } catch (err) {
    console.error(`[refresh-due-flights] pre-departure reminder failed for ${updated.id}:`, (err as Error).message);
    await releaseReminder(serviceClient, updated.id, "pre_departure_notified", {});
  }
}

export type FlightRefreshResult =
  | { ok: true; refreshed: number; skipped: number; deferred?: number; alreadyRunning?: boolean }
  | { ok: false; status: number; error: string };

export interface FlightRefreshOptions {
  // Every tracked flight the run should consider. Tests pass their own seeded flights.
  loadTrackedFlights?: (serviceClient: SupabaseClient) => Promise<FlightRow[] | null>;
  // The flat live-position pass after the main loop.
  syncLivePositions?: (serviceClient: SupabaseClient) => Promise<void>;
  maxRefreshesPerRun?: number;
  interCallDelayMs?: number;
  clock?: () => number;
}

export async function runDueFlightRefresh(
  serviceClient: SupabaseClient,
  options: FlightRefreshOptions = {},
): Promise<FlightRefreshResult> {
  // One run at a time (DB-5): pg_cron starts a run every minute without waiting for the last one.
  // A run that finds the lease held leaves the work to the run holding it.
  const { data: holder, error: leaseErr } = await serviceClient.rpc("claim_cron_lease", {
    p_job: LEASE_JOB,
    p_ttl_seconds: LEASE_TTL_SECONDS,
  });
  if (leaseErr) {
    console.error("[refresh-due-flights] failed to claim the run lease:", leaseErr.message);
    return { ok: false, status: 500, error: "Failed to claim the run lease" };
  }
  if (!holder) {
    console.log("[refresh-due-flights] previous run still going; skipping this tick");
    return { ok: true, refreshed: 0, skipped: 0, alreadyRunning: true };
  }

  try {
    return await refreshTrackedFlights(serviceClient, options);
  } finally {
    const { error } = await serviceClient.rpc("release_cron_lease", { p_job: LEASE_JOB, p_holder: holder });
    if (error) console.error("[refresh-due-flights] failed to release the run lease:", error.message);
  }
}

async function refreshTrackedFlights(
  serviceClient: SupabaseClient,
  options: FlightRefreshOptions,
): Promise<FlightRefreshResult> {
  const clock = options.clock ?? Date.now;
  const startedAt = clock();
  const now = startedAt;
  const maxRefreshes = options.maxRefreshesPerRun ?? MAX_REFRESHES_PER_RUN;
  const interCallDelayMs = options.interCallDelayMs ?? INTER_CALL_DELAY_MS;

  const flights = await (options.loadTrackedFlights ?? loadTrackedFlights)(serviceClient);
  if (!flights) return { ok: false, status: 500, error: "Failed to load flights" };

  // Already done (successfully or not) — no point asking AeroAPI for more; those only go through
  // reconcileOverdueArrival below so they get archived (tracking_enabled = false) once it's been
  // 2 hours since arrival.
  const due = dueFlightsInOrder(flights.filter((f) => !TERMINAL_STATUSES.includes(f.status)), now);
  const dueIds = new Set(due.map((f) => f.id));

  let refreshed = 0;
  let deferred = 0;
  let rateLimited = false;

  for (const [index, flight] of due.entries()) {
    // Bounded, so a run never outlasts its minute however many flights are due. Whatever is left
    // is still due next minute, and by then later against its cadence, so it moves up the order.
    // The first flight always goes, so a run always makes progress.
    const outOfTime = index > 0 && clock() - startedAt >= REFRESH_BUDGET_MS;
    if (rateLimited || outOfTime || index >= maxRefreshes) {
      deferred = due.length - index;
      console.log(
        `[refresh-due-flights] ${deferred} due flights left for the next run (${
          rateLimited ? "rate limited" : outOfTime ? "out of time" : "per-run limit"
        })`,
      );
      for (const rest of due.slice(index)) await reconcile(serviceClient, rest, now);
      break;
    }

    let latest: FlightRow = flight;
    try {
      const updated = await refreshOneFlight(serviceClient, flight, "refresh-due-flights");
      refreshed++;
      if (updated) latest = updated;

      if (updated) await maybeSendPreDepartureReminder(serviceClient, updated, now);

      if (updated) {
        try {
          await maybeSendArrivalReminders(serviceClient, updated, now);
        } catch (err) {
          console.error(`[refresh-due-flights] arrival reminder check failed for ${flight.id}:`, (err as Error).message);
        }
      }
    } catch (err) {
      console.error(`[refresh-due-flights] refresh failed for ${flight.id}:`, (err as Error).message);
      // AeroAPI asked us to slow down, and already refused the one retry. Asking about the
      // remaining flights now would only be refused too, and each refusal is still billed.
      if (err instanceof AeroApiError && err.status === 429) rateLimited = true;
    }

    if (!rateLimited) {
      try {
        await maybeRefreshWeather(serviceClient, flight, "refresh-due-flights");
      } catch (err) {
        console.error(`[refresh-due-flights] weather refresh failed for ${flight.id}:`, (err as Error).message);
      }
    }

    // Catches two cases in one pass: AeroAPI just went silent on this refresh too (still
    // non-terminal well past best-known arrival — force it to "arrived"), or it just became
    // terminal this tick (actual_in freshly confirmed — too recent to archive yet, no-ops until
    // 2 hours from now).
    await reconcile(serviceClient, latest, now);

    if (interCallDelayMs > 0) await new Promise((resolve) => setTimeout(resolve, interCallDelayMs));
  }

  // Not due, or terminal: no AeroAPI call, but a flight the provider has gone silent on still needs
  // forcing to arrived, and a landed one archiving.
  for (const flight of flights) {
    if (!dueIds.has(flight.id)) await reconcile(serviceClient, flight, now);
  }

  // A separate, flat pass — deduped by fa_flight_id across every couple tracking the same
  // real-world flight (see syncLivePositions' own doc comment), run every cron tick regardless of
  // isDue()'s AeroAPI-staleness tiering above. Deliberately after the main loop, not before, so a
  // flight that just transitioned to airborne *this tick* (via refreshOneFlight's AeroAPI update)
  // is already picked up by this pass's own fresh query rather than waiting a full extra minute.
  try {
    if (options.syncLivePositions) {
      await options.syncLivePositions(serviceClient);
    } else {
      await syncLivePositions(serviceClient, startedAt + RUN_DEADLINE_MS, clock);
    }
  } catch (err) {
    console.error("[refresh-due-flights] syncLivePositions failed:", (err as Error).message);
  }

  return { ok: true, refreshed, skipped: flights.length - due.length, deferred };
}

async function reconcile(serviceClient: SupabaseClient, flight: FlightRow, now: number): Promise<void> {
  try {
    await reconcileOverdueArrival(serviceClient, flight, now);
  } catch (err) {
    console.error(`[refresh-due-flights] reconcileOverdueArrival failed for ${flight.id}:`, (err as Error).message);
  }
}
