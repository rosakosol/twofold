import type { ReactNode } from "react";

/** One row of an accordion (docs/TWOFOLD_WEBSITE.md, section 3): a native <details>, so the
 *  keyboard, the open state and what a screen reader announces all come from the browser. Wrap a
 *  group in <div className="accordion">; open the first item of each group. */
export function AccordionItem({
  title,
  children,
  defaultOpen = false,
  id,
}: {
  title: ReactNode;
  children: ReactNode;
  defaultOpen?: boolean;
  id?: string;
}) {
  return (
    <details className="accordion-item" open={defaultOpen} id={id}>
      <summary>
        <span>{title}</span>
        <span className="accordion-sign" aria-hidden />
      </summary>
      <div className="accordion-body">{children}</div>
    </details>
  );
}
