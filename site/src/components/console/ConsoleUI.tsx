import type { ReactNode } from "react";

/*
 * The console's page furniture (docs/TWOFOLD_WEBSITE.md, section 9.2): the same tokens as the site,
 * in the console's denser layout. Styles are src/styles/console.css.
 */

/** The top of every console page: a 34px title, one line saying what the page is for, and the
 *  page's actions on the right. */
export function ConsolePageHead({ title, description, actions }: { title: string; description?: ReactNode; actions?: ReactNode }) {
  return (
    <header className="console-head">
      <div>
        <h1>{title}</h1>
        {description && <p>{description}</p>}
      </div>
      {actions && <div className="console-head-actions">{actions}</div>}
    </header>
  );
}

export interface StatTileItem {
  label: string;
  value: ReactNode;
  /** A line under the value, if the number needs one. */
  hint?: ReactNode;
}

/** A row of stat tiles: a label over a large figure. */
export function StatTiles({ items }: { items: StatTileItem[] }) {
  return (
    <dl className="console-stats">
      {items.map((item) => (
        <div key={item.label} className="console-stat">
          <dt>{item.label}</dt>
          <dd>{item.value}</dd>
          {item.hint && <p className="console-stat-hint">{item.hint}</p>}
        </div>
      ))}
    </dl>
  );
}

/** An empty list: what is missing, and why, rather than a blank table. */
export function ConsoleEmpty({ title, children, tone }: { title: string; children?: ReactNode; tone?: "success" }) {
  return (
    <div className={`console-empty${tone === "success" ? " is-success" : ""}`}>
      <p className="console-empty-title">{title}</p>
      {children && <div className="console-empty-body">{children}</div>}
    </div>
  );
}

/**
 * A read that failed, said as such. The counterpart to ConsoleEmpty, and deliberately unlike it: an
 * empty state says "nothing needs you", and a failed read must never look like one. `onRetry` is
 * optional so server markup can use it too; client pages pass their query's `refetch`.
 */
export function ConsoleError({
  title = "This didn't load",
  children,
  onRetry,
}: {
  title?: string;
  children?: ReactNode;
  onRetry?: () => void;
}) {
  return (
    <div className="console-empty is-error" role="alert">
      <p className="console-empty-title">{title}</p>
      <div className="console-empty-body">
        {children ?? "The read failed, so nothing below is known to be empty. Try again, or check the logs if it keeps happening."}
      </div>
      {onRetry && (
        <button type="button" className="btn btn-secondary btn-sm console-empty-action" onClick={onRetry}>
          Try again
        </button>
      )}
    </div>
  );
}
