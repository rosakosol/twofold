import type { ReactNode } from "react";

export type HaloTint = "coral" | "green" | "blue" | "indigo" | "paper";

/** The glow and dashed ring behind a feature visual (docs/TWOFOLD_WEBSITE.md, section 3).
 *  Decorative, so it is drawn with pseudo-elements and never reaches the accessibility tree. */
export function GlowHalo({ tint, children, className }: { tint: HaloTint; children: ReactNode; className?: string }) {
  return <div className={["glow-halo", `halo-${tint}`, className].filter(Boolean).join(" ")}>{children}</div>;
}
