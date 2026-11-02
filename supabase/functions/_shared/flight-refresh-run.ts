// The body of the `refresh-due-flights` cron, kept out of its index.ts so tests can import it:
// that file's top-level `Deno.serve` starts a server on import. The cadence it applies is
// documented at the top of refresh-due-flights/index.ts and lives in flight-schedule.ts.

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import {
  type FlightRow,
  maybeRefreshWeather,
  reconcileOverdueArrival,
  refreshOneFlight,
  syncLivePositions,
} from "./flight-sync.ts";
import { notifyArrivalReminder, notifyPreDeparture } from "./notify.ts";
import {
  ARRIVAL_REMINDER_1H_WINDOW_MS,
  ARRIVAL_REMINDER_30M_WINDOW_MS,
  bestKnownArrival,
  isDue,
  isDueForArrivalReminder,
  isDueForPreDepartureReminder,
  shouldResetArrivalReminder,
} from "./flight-schedule.ts";

const TERMINAL_STATUSES = ["arrived", "landed", "cancelled", "diverted"];

const INTER_CALL_DELAY_MS = 200;

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
      await notifyArrivalReminder(serviceClient, updated.id, window);
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
    await notifyPreDeparture(serviceClient, updated.id);
  } catch (err) {
    console.error(`[refresh-due-flights] pre-departure reminder failed for ${updated.id}:`, (err as Error).message);
    await releaseReminder(serviceClient, updated.id, "pre_departure_notified", {});
  }
}

export type FlightRefreshResult =
  | { ok: true; refreshed: number; skipped: number; alreadyRunning?: boolean }
  | { ok: false; status: number; error: string };

// Every tracked flight of an active couple, or null when they couldn't be loaded.
async function loadTrackedFlights(serviceClient: SupabaseClient): Promise<FlightRow[] | null> {
  // Defense in depth, not just a fix for one call site: `tracking_enabled` alone doesn't catch
  // every way a flight can become orphaned — a couple dissolving is the confirmed case
  // (`leave_couple` now clears it directly, see 20260723000000), but this guards against any
  // *other* path that leaves tracking_enabled = true on a flight whose couple can no longer load
  // it client-side (fetchCoupleState() only ever loads active couples), which would otherwise
  // poll AeroAPI for it every 5 minutes forever with nobody able to see the result.
  const { data: activeCouples, error: couplesErr } = await serviceClient
    .from("couples")
    .select("id")
    .eq("status", "active");
  if (couplesErr) {
    console.error("[refresh-due-flights] failed to load active couples:", couplesErr.message);
    return null;
  }
  const activeCoupleIds = (activeCouples ?? []).map((c) => c.id as string);
  if (activeCoupleIds.length === 0) {
    return [];
  }

  const { data: flights, error } = await serviceClient
    .from("flights")
    .select("*")
    .eq("tracking_enabled", true)
    .in("couple_id", activeCoupleIds);

  if (error) {
    console.error("[refresh-due-flights] failed to load flights:", error.message);
    return null;
  }

  return (flights ?? []) as FlightRow[];
}

export interface FlightRefreshOptions {
  // Every tracked flight the run should consider. Tests pass their own seeded flights.
  loadTrackedFlights?: (serviceClient: SupabaseClient) => Promise<FlightRow[] | null>;
  // The flat live-position pass after the main loop.
  syncLivePositions?: (serviceClient: SupabaseClient) => Promise<void>;
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
  const flights = await (options.loadTrackedFlights ?? loadTrackedFlights)(serviceClient);
  if (!flights) return { ok: false, status: 500, error: "Failed to load flights" };

  let refreshed = 0;
  let skipped = 0;
  const now = Date.now();

  for (const flight of flights) {
    // Already done (successfully or not) — no point asking AeroAPI for more, but still run
    // through reconcileOverdueArrival below so it gets archived (tracking_enabled = false) once
    // it's been 2 hours since arrival.
    if (TERMINAL_STATUSES.includes(flight.status)) {
      skipped++;
      try {
        await reconcileOverdueArrival(serviceClient, flight, now);
      } catch (err) {
        console.error(`[refresh-due-flights] reconcileOverdueArrival failed for ${flight.id}:`, (err as Error).message);
      }
      continue;
    }

    if (!isDue(flight, now)) {
      skipped++;
      try {
        await reconcileOverdueArrival(serviceClient, flight, now);
      } catch (err) {
        console.error(`[refresh-due-flights] reconcileOverdueArrival failed for ${flight.id}:`, (err as Error).message);
      }
      continue;
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
    }

    try {
      await maybeRefreshWeather(serviceClient, flight, "refresh-due-flights");
    } catch (err) {
      console.error(`[refresh-due-flights] weather refresh failed for ${flight.id}:`, (err as Error).message);
    }

    // Catches two cases in one pass: AeroAPI just went silent on this refresh too (still
    // non-terminal well past best-known arrival — force it to "arrived"), or it just became
    // terminal this tick (actual_in freshly confirmed — too recent to archive yet, no-ops until
    // 2 hours from now).
    try {
      await reconcileOverdueArrival(serviceClient, latest, now);
    } catch (err) {
      console.error(`[refresh-due-flights] reconcileOverdueArrival failed for ${flight.id}:`, (err as Error).message);
    }

    await new Promise((resolve) => setTimeout(resolve, INTER_CALL_DELAY_MS));
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
      // Every airborne tracked flight belongs to one of these couples.
      await syncLivePositions(serviceClient, [...new Set(flights.map((f) => f.couple_id))]);
    }
  } catch (err) {
    console.error("[refresh-due-flights] syncLivePositions failed:", (err as Error).message);
  }

  return { ok: true, refreshed, skipped };
}
