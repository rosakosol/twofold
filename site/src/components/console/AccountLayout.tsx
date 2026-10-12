import type { ReactNode } from "react";

/*
 * The account page's furniture (src/styles/console.css, "One account"): a titled section, a card
 * that stands off the page, label/value rows, and a row with an action on it. No state and no
 * client code, so the server page and the client action components draw the same shapes.
 */

export function AccountSection({
  id,
  title,
  icon,
  description,
  className,
  children,
}: {
  id: string;
  title: string;
  icon?: ReactNode;
  /** One short line beside the heading. */
  description?: ReactNode;
  className?: string;
  children: ReactNode;
}) {
  return (
    <section id={id} aria-labelledby={`${id}-title`} className={["account-section", className].filter(Boolean).join(" ")}>
      <div className="account-section-head">
        <h2 id={`${id}-title`}>
          {icon}
          {title}
        </h2>
        {description && <p>{description}</p>}
      </div>
      {children}
    </section>
  );
}

export function AccountCard({
  title,
  action,
  description,
  children,
}: {
  title: ReactNode;
  /** A link or control on the right of the title. */
  action?: ReactNode;
  description?: ReactNode;
  children?: ReactNode;
}) {
  return (
    <div className="account-card">
      <div className="account-card-head">
        <h3>{title}</h3>
        {action}
      </div>
      {description && <p className="account-card-sub">{description}</p>}
      {children}
    </div>
  );
}

export function Facts({ children }: { children: ReactNode }) {
  return <dl className="account-facts">{children}</dl>;
}

/** One label/value row. `alert` is for a value that needs acting on, not for decoration. */
export function Fact({ label, value, alert }: { label: string; value: ReactNode; alert?: boolean }) {
  return (
    <div className={alert ? "is-alert" : undefined}>
      <dt>{label}</dt>
      <dd>{value}</dd>
    </div>
  );
}

/** A row in a list of things that can be done: the title, one line about it, where it stands now,
 *  and the button that opens its dialog. Rendered inside `<ul className="account-actions">`. */
export function ActionRow({
  title,
  info,
  description,
  value,
  children,
}: {
  title: ReactNode;
  /** An InfoTip beside the title, for the longer "why". */
  info?: ReactNode;
  description: ReactNode;
  value?: ReactNode;
  /** The button, usually a dialog trigger. Absent when there is nothing to offer. */
  children?: ReactNode;
}) {
  return (
    <li>
      <div className="account-action">
        <div className="account-action-text">
          <p className="account-action-title">
            {title}
            {info}
          </p>
          <p className="account-action-desc">{description}</p>
        </div>
        {value !== undefined && <div className="account-action-value">{value}</div>}
        {children && <div className="account-action-button">{children}</div>}
      </div>
    </li>
  );
}
