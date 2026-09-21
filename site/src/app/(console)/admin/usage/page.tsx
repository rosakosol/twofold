import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { UsageMeter } from "@/components/console/usage/UsageMeter";
import { UsageTrend, type UsageDay } from "@/components/console/usage/UsageTrend";
import { UsageEndpointTable, type UsageEndpoint } from "@/components/console/usage/UsageEndpointTable";

export const metadata: Metadata = { title: "API usage" };

// Spend moves with every cron tick and the rollup restates the current day hourly, so a cached
// page would show a number that is quietly hours old on a screen whose entire job is to be current.
export const dynamic = "force-dynamic";

/**
 * What AeroAPI costs, read from our own record of every call rather than from FlightAware's
 * dashboard.
 *
 * The group layout only checks that the caller is *an* admin. Spend is gated separately on the
 * `billing` role — the whole reason that role is distinct is that seeing what the app costs should
 * not require being trusted with anybody's account, and the converse holds too: editing a trivia
 * deck is not a reason to see the business's numbers. The RPCs enforce this themselves and raise
 * 42501; this check is so a content admin gets a redirect rather than an error page.
 */
export default async function UsagePage() {
  const supabase = await createClient();

  // The gate joins the batch rather than gating it, for the same reason as the account page: each
  // of these RPCs enforces is_billing_admin() itself, so running them together costs a non-admin
  // three refusals and saves every real load a round trip to Sydney.
  const [{ data: isBillingAdmin }, summaryResult, endpointResult, seriesResult] = await Promise.all([
    supabase.rpc("is_billing_admin"),
    supabase.rpc("api_usage_summary", { p_provider: "aeroapi" }),
    supabase.rpc("api_usage_by_endpoint", { p_provider: "aeroapi" }),
    supabase.rpc("api_usage_daily_series", { p_provider: "aeroapi" }),
  ]);

  if (isBillingAdmin !== true) redirect("/admin");

  // `api_usage_summary` returns a single row; supabase-js gives a one-element array for a
  // table-returning function.
  const summary = Array.isArray(summaryResult.data) ? summaryResult.data[0] : null;
  const endpoints = (endpointResult.data ?? []) as UsageEndpoint[];
  const days = (seriesResult.data ?? []) as UsageDay[];

  return (
    <div className="space-y-6">
      <header>
        <h1 className="font-heading text-xl font-semibold tracking-tight">API usage</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          AeroAPI · this month, and the last 30 days
        </p>
      </header>

      <UsageMeter
        utilisationPercent={numberOrNull(summary?.list_utilisation_percent)}
        minimumUsd={numberOrNull(summary?.monthly_minimum_usd)}
        listCostUsd={numberOrNull(summary?.list_cost_usd) ?? 0}
        projectedUsd={numberOrNull(summary?.projected_list_usd)}
      />

      <UsageTrend days={days} />

      <UsageEndpointTable rows={endpoints} />
    </div>
  );
}

/** Postgres numerics arrive as strings over PostgREST, so every figure here needs coercing before
 * it is formatted — `toFixed` on a string throws, and `"7.04" + 0` would concatenate. */
function numberOrNull(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}
