// 60-day historical on-time-performance stats for a flight *designator* (e.g. "UAE1") — distinct
// from the rest of flight-sync.ts's poll/diff/notify pipeline, which is all about one specific
// tracked instance (fa_flight_id). Deduped by ident and cached ~24h in flight_delay_stats (see
// the matching migration), computed on demand by flight-delay-stats/index.ts, never proactively
// by the cron — this is the one piece of this session's AeroAPI work where background-computing
// it for every tracked flight would be pure waste (nobody's looking at most of them).

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { type AeroFlight, fetchHistoricalFlights } from "./aeroapi.ts";

export interface DelayStats {
  observedCount: number;
  latePercent: number;
  averageLateMinutes: number;
  earlyPercent: number;
  onTimePercent: number;
  late15Percent: number;
  late30Percent: number;
  late45Percent: number;
  cancelledPercent: number;
  divertedPercent: number;
}

const CACHE_TTL_MS = 24 * 60 * 60 * 1000;
const LOOKBACK_DAYS = 60;

interface DelayStatsRow {
  ident: string;
  observed_count: number;
  late_percent: number;
  average_late_minutes: number;
  early_percent: number;
  on_time_percent: number;
  late_15_percent: number;
  late_30_percent: number;
  late_45_percent: number;
  cancelled_percent: number;
  diverted_percent: number;
  computed_at: string;
}

function toDelayStats(row: DelayStatsRow): DelayStats {
  return {
    observedCount: row.observed_count,
    latePercent: row.late_percent,
    averageLateMinutes: row.average_late_minutes,
    earlyPercent: row.early_percent,
    onTimePercent: row.on_time_percent,
    late15Percent: row.late_15_percent,
    late30Percent: row.late_30_percent,
    late45Percent: row.late_45_percent,
    cancelledPercent: row.cancelled_percent,
    divertedPercent: row.diverted_percent,
  };
}

type Bucket = "early" | "onTime" | "late15" | "late30" | "late45" | "cancelled" | "diverted";

function bucketFor(flight: AeroFlight): Bucket | null {
  if (flight.cancelled) return "cancelled";
  if (flight.diverted) return "diverted";

  const scheduled = flight.scheduled_out;
  const actual = flight.actual_out ?? flight.estimated_out;
  if (!scheduled || !actual) return null; // incomplete/not-yet-happened — never fabricate a bucket

  const delayMinutes = (new Date(actual).getTime() - new Date(scheduled).getTime()) / 60_000;
  if (delayMinutes < 0) return "early";
  if (delayMinutes < 15) return "onTime";
  if (delayMinutes < 30) return "late15";
  if (delayMinutes < 45) return "late30";
  return "late45";
}

function percent(count: number, total: number): number {
  return total === 0 ? 0 : (count / total) * 100;
}

export async function computeDelayStats(serviceClient: SupabaseClient, ident: string): Promise<DelayStats> {
  const { data: cached } = await serviceClient
    .from("flight_delay_stats")
    .select("*")
    .eq("ident", ident)
    .maybeSingle();

  const cachedRow = cached as DelayStatsRow | null;
  if (cachedRow && Date.now() - new Date(cachedRow.computed_at).getTime() < CACHE_TTL_MS) {
    return toDelayStats(cachedRow);
  }

  const end = new Date();
  const start = new Date(end.getTime() - LOOKBACK_DAYS * 24 * 60 * 60 * 1000);
  const flights = await fetchHistoricalFlights(ident, start.toISOString(), end.toISOString());

  const counts: Record<Bucket, number> = {
    early: 0, onTime: 0, late15: 0, late30: 0, late45: 0, cancelled: 0, diverted: 0,
  };
  const lateDelayMinutes: number[] = [];

  for (const flight of flights) {
    const bucket = bucketFor(flight);
    if (!bucket) continue;
    counts[bucket]++;
    if (bucket === "late15" || bucket === "late30" || bucket === "late45") {
      const actual = flight.actual_out ?? flight.estimated_out;
      if (actual && flight.scheduled_out) {
        lateDelayMinutes.push((new Date(actual).getTime() - new Date(flight.scheduled_out).getTime()) / 60_000);
      }
    }
  }

  const observed = Object.values(counts).reduce((sum, n) => sum + n, 0);
  const lateCount = counts.late15 + counts.late30 + counts.late45;
  const averageLateMinutes = lateDelayMinutes.length === 0
    ? 0
    : lateDelayMinutes.reduce((sum, m) => sum + m, 0) / lateDelayMinutes.length;

  const row: DelayStatsRow = {
    ident,
    observed_count: observed,
    late_percent: percent(lateCount, observed),
    average_late_minutes: averageLateMinutes,
    early_percent: percent(counts.early, observed),
    on_time_percent: percent(counts.onTime, observed),
    late_15_percent: percent(counts.late15, observed),
    late_30_percent: percent(counts.late30, observed),
    late_45_percent: percent(counts.late45, observed),
    cancelled_percent: percent(counts.cancelled, observed),
    diverted_percent: percent(counts.diverted, observed),
    computed_at: new Date().toISOString(),
  };

  const { error } = await serviceClient.from("flight_delay_stats").upsert(row, { onConflict: "ident" });
  if (error) {
    console.error(`[delay-stats] failed to upsert stats for ${ident}:`, error.message);
  }

  return toDelayStats(row);
}
