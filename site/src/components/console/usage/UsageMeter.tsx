import { Card, CardContent } from "@/components/ui/card";

/**
 * The hero figure, and the one decision this page is built around.
 *
 * It leads with utilisation of the monthly minimum rather than with spend, because below the floor
 * spend does not move: AeroAPI bills max($100, discounted usage), and usage is nowhere near it. A
 * dashboard whose headline is "$0.59" would report a flat line every month and say nothing, while
 * the thing worth knowing — how much of what we already pay for is being used, and how much room
 * is left — would be nowhere on it.
 *
 * A meter rather than a chart: this is a single ratio against a limit, which is what a meter is
 * for and what a two-slice pie would be a worse version of. The track is a lighter step of the
 * fill's own ramp so the state reads across the whole bar, and the fill carries severity.
 *
 * The percentage is always written out beside it. That is not decoration — the accent step sits
 * below 3:1 against the light surface, and the validator's relief for that is visible labels.
 */
export function UsageMeter({
  utilisationPercent,
  minimumUsd,
  listCostUsd,
  projectedUsd,
}: {
  utilisationPercent: number | null;
  minimumUsd: number | null;
  listCostUsd: number;
  projectedUsd: number | null;
}) {
  const pct = utilisationPercent ?? 0;
  // Severity, and each state also says its name below — status colour never carries meaning alone.
  const state = pct >= 100 ? "over" : pct >= 70 ? "close" : "clear";
  const fill =
    state === "over" ? "var(--usage-danger)" : state === "close" ? "var(--usage-warning)" : "var(--usage-accent)";

  return (
    <Card>
      <CardContent className="pt-6">
        <p className="text-sm text-muted-foreground">Used of your monthly minimum</p>

        {/* Proportional figures, not tabular: tabular-nums gives every digit the width of a zero,
            which reads loose at display sizes. Tabular is for the columns in the table below. */}
        <p className="mt-1 text-5xl font-semibold tracking-tight">
          {utilisationPercent === null ? "—" : `${Math.round(pct)}%`}
        </p>

        <div
          className="mt-4 h-2.5 w-full overflow-hidden rounded-full"
          style={{ background: "var(--usage-accent-track)" }}
          role="meter"
          aria-valuenow={Math.round(pct)}
          aria-valuemin={0}
          aria-valuemax={100}
          aria-label="Share of the monthly minimum used"
        >
          <div
            className="h-full rounded-full transition-[width] duration-500"
            style={{ width: `${Math.min(100, Math.max(0, pct))}%`, background: fill }}
          />
        </div>

        <p className="mt-3 text-sm text-muted-foreground">
          {state === "over"
            ? "Over the minimum — usage now costs more than the floor."
            : state === "close"
              ? "Approaching the minimum. Past it, calls start costing real money."
              : "Well inside the minimum. Every call is already paid for."}
        </p>

        <dl className="mt-4 grid grid-cols-3 gap-4 border-t pt-4 text-sm">
          <div>
            <dt className="text-muted-foreground">This month</dt>
            <dd className="mt-0.5 font-medium">{money(listCostUsd)}</dd>
          </div>
          <div>
            <dt className="text-muted-foreground">Projected</dt>
            <dd className="mt-0.5 font-medium">{projectedUsd === null ? "—" : money(projectedUsd)}</dd>
          </div>
          <div>
            <dt className="text-muted-foreground">Minimum</dt>
            <dd className="mt-0.5 font-medium">{minimumUsd === null ? "—" : money(minimumUsd)}</dd>
          </div>
        </dl>

        <p className="mt-4 text-xs text-muted-foreground">
          Every figure here is <strong>list price</strong>, computed from our own call counts. What
          you actually pay is <code>max(minimum, discounted usage)</code>, and FlightAware does not
          publish its volume-discount curve — so the discount is observed from invoices rather than
          modelled. Record a closed month in <code>private.api_invoices</code> and the ratio starts
          building.
        </p>
      </CardContent>
    </Card>
  );
}

function money(value: number): string {
  return `$${value.toFixed(2)}`;
}
