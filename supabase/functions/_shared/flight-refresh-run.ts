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

export async function maybeSendArrivalReminders(serviceClient: SupabaseClient, updated: FlightRow, now: number): Promise<void> {
  const currentArrival = bestKnownArrival(updated);

  let arrival1hNotified = updated.arrival_1h_notified;
  let arrival30mNotified = updated.arrival_30m_notified;
  const resetPatch: Record<string, unknown> = {};

  if (arrival1hNotified && shouldResetArrivalReminder(updated.arrival_1h_notified_for, currentArrival)) {
    arrival1hNotified = false;
    resetPatch.arrival_1h_notified = false;
    resetPatch.arrival_1h_notified_for = null;
  }
  if (arrival30mNotified && shouldResetArrivalReminder(updated.arrival_30m_notified_for, currentArrival)) {
    arrival30mNotified = false;
    resetPatch.arrival_30m_notified = false;
    resetPatch.arrival_30m_notified_for = null;
  }
  if (Object.keys(resetPatch).length > 0) {
    const { error } = await serviceClient.from("flights").update(resetPatch).eq("id", updated.id);
    if (error) console.error(`[refresh-due-flights] failed to reset arrival reminder flags for ${updated.id}:`, error.message);
  }

  if (isDueForArrivalReminder(updated, now, ARRIVAL_REMINDER_1H_WINDOW_MS, arrival1hNotified)) {
    try {
      await notifyArrivalReminder(serviceClient, updated.id, "1h");
      await serviceClient
        .from("flights")
        .update({ arrival_1h_notified: true, arrival_1h_notified_for: currentArrival })
        .eq("id", updated.id);
    } catch (err) {
      console.error(`[refresh-due-flights] 1h arrival reminder failed for ${updated.id}:`, (err as Error).message);
    }
  }
  if (isDueForArrivalReminder(updated, now, ARRIVAL_REMINDER_30M_WINDOW_MS, arrival30mNotified)) {
    try {
      await notifyArrivalReminder(serviceClient, updated.id, "30m");
      await serviceClient
        .from("flights")
        .update({ arrival_30m_notified: true, arrival_30m_notified_for: currentArrival })
        .eq("id", updated.id);
    } catch (err) {
      console.error(`[refresh-due-flights] 30m arrival reminder failed for ${updated.id}:`, (err as Error).message);
    }
  }
}

export type FlightRefreshResult =
  | { ok: true; refreshed: number; skipped: number }
  | { ok: false; status: number; error: string };

export async function runDueFlightRefresh(serviceClient: SupabaseClient): Promise<FlightRefreshResult> {
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
    return { ok: false, status: 500, error: "Failed to load active couples" };
  }
  const activeCoupleIds = (activeCouples ?? []).map((c) => c.id as string);
  if (activeCoupleIds.length === 0) {
    return { ok: true, refreshed: 0, skipped: 0 };
  }

  const { data: flights, error } = await serviceClient
    .from("flights")
    .select("*")
    .eq("tracking_enabled", true)
    .in("couple_id", activeCoupleIds);

  if (error) {
    console.error("[refresh-due-flights] failed to load flights:", error.message);
    return { ok: false, status: 500, error: "Failed to load flights" };
  }

  let refreshed = 0;
  let skipped = 0;
  const now = Date.now();

  for (const flight of (flights ?? []) as FlightRow[]) {
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

      if (updated && isDueForPreDepartureReminder(updated, now)) {
        try {
          await notifyPreDeparture(serviceClient, updated.id);
          await serviceClient.from("flights").update({ pre_departure_notified: true }).eq("id", updated.id);
        } catch (err) {
          // Left unmarked on failure so the next cron tick retries — same reasoning as everything
          // else in this loop being best-effort per flight.
          console.error(`[refresh-due-flights] pre-departure reminder failed for ${flight.id}:`, (err as Error).message);
        }
      }

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
    await syncLivePositions(serviceClient, activeCoupleIds);
  } catch (err) {
    console.error("[refresh-due-flights] syncLivePositions failed:", (err as Error).message);
  }

  return { ok: true, refreshed, skipped };
}
