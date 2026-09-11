import type { ResolvedPlanComparison } from "@/lib/marketing/planComparisonFallback";
import { Reveal } from "@/components/marketing/Reveal";

// A cell's text is rendered as written, with two conventions the schema's field descriptions
// spell out for editors: an empty value means "not included" and draws a dash, and the exact
// word "Yes" draws a tick instead of the word. Everything else ("5", "Unlimited", "2000+")
// prints verbatim, which is what most rows here actually need — the two plans mostly differ
// by amount rather than by yes/no.
function Cell({ value, plan }: { value: string; plan: string }) {
  if (!value) {
    return (
      <td className="compare-cell" data-state="no">
        <span aria-label={`Not included in ${plan}`}>&mdash;</span>
      </td>
    );
  }
  if (value.trim().toLowerCase() === "yes") {
    return (
      <td className="compare-cell" data-state="yes">
        <svg className="icon" role="img" aria-label={`Included in ${plan}`}>
          <use href="/assets/icons.svg#icon-check" />
        </svg>
      </td>
    );
  }
  return <td className="compare-cell">{value}</td>;
}

export function PlanComparison({ comparison }: { comparison: ResolvedPlanComparison }) {
  return (
    <Reveal className="compare-wrap">
      <h2 id="compare-heading">{comparison.heading}</h2>
      {comparison.intro && <p className="compare-intro">{comparison.intro}</p>}

      {/* Scrolls inside itself rather than widening the page — three columns of copy don't
          fit a narrow phone, and a horizontally scrolling <body> breaks every other section. */}
      <div className="compare-scroll" tabIndex={0} role="group" aria-labelledby="compare-heading">
        <table className="compare-table">
          <thead>
            <tr>
              <th scope="col">Feature</th>
              <th scope="col">Plus</th>
              <th scope="col">Premium</th>
            </tr>
          </thead>
          <tbody>
            {comparison.rows.map((row) => (
              <tr key={row.label}>
                <th scope="row">{row.label}</th>
                <Cell value={row.plus} plan="Twofold Plus" />
                <Cell value={row.premium} plan="Twofold Premium" />
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Reveal>
  );
}
