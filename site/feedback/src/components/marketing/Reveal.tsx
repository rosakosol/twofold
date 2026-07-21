"use client";

import { useReveal } from "@/hooks/useReveal";
import { cn } from "@/lib/utils";

/** Thin wrapper around useReveal so page markup can just write
 * <Reveal className="feature-card">...</Reveal> instead of wiring the ref by hand
 * everywhere a .reveal element appears. */
export function Reveal({
  as: Tag = "div",
  className,
  children,
  ...props
}: {
  as?: "div" | "section" | "article";
  className?: string;
  children: React.ReactNode;
} & React.HTMLAttributes<HTMLDivElement>) {
  const ref = useReveal<HTMLDivElement>();
  return (
    <Tag ref={ref} className={cn("reveal", className)} {...props}>
      {children}
    </Tag>
  );
}
