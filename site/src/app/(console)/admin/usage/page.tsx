import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { UsageMeter } from "@/components/console/usage/UsageMeter";
import { UsageTrend, type UsageDay } from "@/components/console/usage/UsageTrend";
import { UsageEndpointTable, type UsageEndpoint } from "@/components/console/usage/UsageEndpointTable";
import { ConsolePageHead } from "@/components/console/ConsoleUI";
import { TriangleAlert } from "lucide-react";

/** Calls per distinct flight above which an endpoint is called out: one flight polled this many
 *  times is worth a fetch-once-apply-to-many change. */
const RATIO_WORTH_A_LOOK = 10;

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

  const hot = endpoints
    .map((e) => ({ endpoint: e.endpoint, ratio: e.distinct_upstream > 0 ? e.calls / e.distinct_upstream : 0 }))
    .filter((e) => e.ratio > RATIO_WORTH_A_LOOK)
    .sort((a, b) => b.ratio - a.ratio);

  return (
    <div className="space-y-6">
      <ConsolePageHead title="API usage" description="AeroAPI, this month and the last 30 days." />

      {hot.length > 0 && (
        <div className="usage-insight" role="note">
          <TriangleAlert aria-hidden />
          <p>
            <strong>
              <code>{hot[0].endpoint}</code> is called {hot[0].ratio.toFixed(1)}× per flight.
            </strong>{" "}
            The same flight is being fetched once per couple tracking it. Fetching it once and applying the result to
            everyone would cut these calls
            {hot.length > 1 ? `, and ${hot.length - 1} other endpoint${hot.length === 2 ? " is" : "s are"} above ${RATIO_WORTH_A_LOOK}× too` : ""}.
          </p>
        </div>
      )}

      <div className="usage-grid">
      <UsageMeter
        utilisationPercent={numberOrNull(summary?.list_utilisation_percent)}
        minimumUsd={numberOrNull(summary?.monthly_minimum_usd)}
        listCostUsd={numberOrNull(summary?.list_cost_usd) ?? 0}
        projectedUsd={numberOrNull(summary?.projected_list_usd)}
      />

      <UsageTrend days={days} />
      </div>

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
