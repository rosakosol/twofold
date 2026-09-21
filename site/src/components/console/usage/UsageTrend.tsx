import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

export interface UsageDay {
  day: string;
  calls: number;
  billable_calls: number;
  errors: number;
  distinct_upstream: number;
  list_cost_usd: number | null;
}

/**
 * Daily call volume, as columns.
 *
 * Calls rather than cost, deliberately. Under the monthly minimum a cost chart is a flat line at a
 * number nobody pays, while the failure this whole system was built to catch — a cadence constant
 * quietly tripling call volume, as refresh-due-flights' 2-minute mid-cruise tier did — shows up
 * here as a step change and nowhere else. It costs nothing, so nothing else would report it.
 *
 * One series, so no legend: the title names it. One hue, sequential, because the job is comparing
 * magnitude across days and not telling series apart. Each column carries a native tooltip with
 * its own numbers, and the same data is in the table below, which is the relief the validator
 * requires for an accent step that sits under 3:1 against the light surface.
 *
 * Inline SVG rather than a charting library: one series of thirty columns does not justify adding
 * a dependency to a bundle that has none.
 */
export function UsageTrend({ days }: { days: UsageDay[] }) {
  if (days.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Daily calls</CardTitle>
          <CardDescription>Nothing recorded yet.</CardDescription>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground">
            Metering starts with the first cron run after this deploys — there is no backfill, so
            this fills in from that point rather than showing history.
          </p>
        </CardContent>
      </Card>
    );
  }

  const max = Math.max(...days.map((d) => d.calls), 1);
  const total = days.reduce((sum, d) => sum + d.calls, 0);
  const peak = days.reduce((best, d) => (d.calls > best.calls ? d : best), days[0]);

  return (
    <Card>
      <CardHeader>
        <CardTitle>Daily calls</CardTitle>
        <CardDescription>
          {total.toLocaleString()} calls over {days.length} day{days.length === 1 ? "" : "s"} · peak{" "}
          {peak.calls.toLocaleString()} on {shortDate(peak.day)}
        </CardDescription>
      </CardHeader>

      <CardContent>
        {/* A flex row of columns rather than a scaled SVG: the bars stay 4px-rounded at their data
            end, keep a real 2px gap between them at any width, and the hit target is the whole
            column rather than the drawn height. */}
        <div className="flex h-40 items-end gap-[2px]" role="img" aria-label={`Daily AeroAPI calls over ${days.length} days`}>
          {days.map((d) => {
            const height = Math.max(2, Math.round((d.calls / max) * 100));
            const hasErrors = d.errors > 0;
            return (
              <div
                key={d.day}
                className="group relative flex-1 rounded-t-[4px] transition-opacity hover:opacity-80"
                style={{
                  height: `${height}%`,
                  background: hasErrors
                    ? `linear-gradient(to top, var(--usage-danger) ${Math.round((d.errors / Math.max(d.calls, 1)) * 100)}%, var(--usage-accent) 0)`
                    : "var(--usage-accent)",
                }}
              >
                <title>
                  {`${shortDate(d.day)} — ${d.calls} calls, ${d.billable_calls} billable, ${d.errors} errors, ${d.distinct_upstream} distinct flights`}
                </title>
              </div>
            );
          })}
        </div>

        <div className="mt-2 flex justify-between text-xs text-muted-foreground tabular-nums">
          <span>{shortDate(days[0].day)}</span>
          <span>{shortDate(days[days.length - 1].day)}</span>
        </div>

        <p className="mt-3 text-xs text-muted-foreground">
          A red foot on a column is the share of that day&apos;s calls that returned an error. Those
          cost nothing — FlightAware bills per page returned — but a run of them means something is
          wrong upstream.
        </p>
      </CardContent>
    </Card>
  );
}

function shortDate(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleDateString(undefined, { month: "short", day: "numeric" });
}
