import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";

export interface UsageEndpoint {
  endpoint: string;
  calls: number;
  billable_calls: number;
  errors: number;
  retries: number;
  distinct_upstream: number;
  list_cost_usd: number | null;
  unit_price_usd: number | null;
}

/**
 * Where the money goes, per billable endpoint class.
 *
 * A table rather than a chart: there are more classes than colour can carry, every column is a
 * number somebody will want to read exactly, and the interesting comparison — calls against
 * distinct flights — is a ratio you read rather than a shape you see.
 *
 * That ratio is the point of the last column. `refresh-due-flights`'s main loop is not deduped by
 * fa_flight_id (only syncLivePositions is, and that pass hits the free ADS-B mirrors), so two
 * couples tracking one real-world flight bill two identical calls per tick. A ratio near 1.0 means
 * nothing is being fetched twice; the further above 1.0 it climbs, the more a fetch-once-apply-to-
 * many change is worth making — and under the monthly minimum, that is a headroom argument rather
 * than a saving.
 */
export function UsageEndpointTable({ rows }: { rows: UsageEndpoint[] }) {
  const priced = rows.filter((r) => r.list_cost_usd !== null);
  const total = priced.reduce((sum, r) => sum + (r.list_cost_usd ?? 0), 0);
  const unpriced = rows.length - priced.length;

  return (
    <Card>
      <CardHeader>
        <CardTitle>By endpoint</CardTitle>
        <CardDescription>
          ${total.toFixed(2)} at list over this window
          {unpriced > 0 && ` · ${unpriced} endpoint${unpriced === 1 ? "" : "s"} with no known price`}
        </CardDescription>
      </CardHeader>

      <CardContent>
        {rows.length === 0 ? (
          <p className="text-sm text-muted-foreground">Nothing recorded in this window yet.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm tabular-nums">
              <thead>
                <tr className="border-b text-left text-xs text-muted-foreground">
                  <th className="pb-2 pr-3 font-medium">Endpoint</th>
                  <th className="pb-2 px-3 text-right font-medium">Calls</th>
                  <th className="pb-2 px-3 text-right font-medium">Billable</th>
                  <th className="pb-2 px-3 text-right font-medium">Errors</th>
                  <th className="pb-2 px-3 text-right font-medium">Cost</th>
                  <th className="pb-2 pl-3 text-right font-medium">Calls / flight</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((row) => {
                  const ratio =
                    row.distinct_upstream > 0 ? row.calls / row.distinct_upstream : null;
                  return (
                    <tr key={row.endpoint} className="border-b last:border-0">
                      <td className="py-2 pr-3 font-mono text-xs">{row.endpoint}</td>
                      <td className="py-2 px-3 text-right">{row.calls.toLocaleString()}</td>
                      <td className="py-2 px-3 text-right">{row.billable_calls.toLocaleString()}</td>
                      <td className="py-2 px-3 text-right">
                        {row.errors > 0 ? (
                          <span style={{ color: "var(--usage-danger)" }}>{row.errors.toLocaleString()}</span>
                        ) : (
                          <span className="text-muted-foreground">0</span>
                        )}
                      </td>
                      <td className="py-2 px-3 text-right">
                        {row.list_cost_usd === null ? (
                          // Never "$0.00". An unknown price is not a free call, and a zero here is
                          // the one reading that would stop anyone investigating it.
                          <Badge variant="outline" className="font-normal">
                            no rate
                          </Badge>
                        ) : (
                          `$${row.list_cost_usd.toFixed(2)}`
                        )}
                      </td>
                      <td className="py-2 pl-3 text-right">
                        {ratio === null ? (
                          <span className="text-muted-foreground">—</span>
                        ) : (
                          <span className={ratio >= 1.5 ? "font-medium" : "text-muted-foreground"}>
                            {ratio.toFixed(1)}×
                          </span>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}

        <p className="mt-4 text-xs text-muted-foreground">
          <strong>Calls / flight</strong> is calls divided by distinct real-world flights touched.
          1.0× means nothing was fetched twice. Higher means the same flight was polled once per
          couple tracking it — <code>refresh-due-flights</code> does not dedupe its main loop, only
          the free ADS-B position pass. Below the monthly minimum, fixing that buys headroom rather
          than money.
        </p>
      </CardContent>
    </Card>
  );
}
