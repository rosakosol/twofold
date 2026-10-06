import type { ReactNode } from "react";

export type PillTone = "neutral" | "accent" | "success" | "warning" | "error" | "indigo" | "surface";

/** A pill: an icon (or a dot) and a word, never colour alone (docs/TWOFOLD_WEBSITE.md, sections 3
 *  and 10). Requested is neutral, Planned accent, In progress warning, Shipped and Match success,
 *  Ended and Deleted error, Premium indigo. */
export function StatusPill({
  tone,
  icon,
  children,
  className,
}: {
  tone: PillTone;
  /** A lucide icon element. Without one the pill gets a dot in its own colour. */
  icon?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <span className={["pill", `pill-${tone}`, icon ? null : "pill-dot", className].filter(Boolean).join(" ")}>
      {icon ? <span aria-hidden className="contents">{icon}</span> : null}
      {children}
    </span>
  );
}
