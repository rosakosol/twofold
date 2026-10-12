"use client";

import type { ReactNode } from "react";
import { Info } from "lucide-react";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";

/**
 * The longer "why" behind a one-line description, one click (or Tab and Enter) away.
 *
 * The account page used to print every one of these in full, which is how it became a wall of
 * text. They are kept, not cut: they are the reasoning a new admin needs once and an experienced
 * one never, so they sit behind a button rather than in front of everybody.
 */
export function InfoTip({ label, children }: { label: string; children: ReactNode }) {
  return (
    <Popover>
      <PopoverTrigger render={<button type="button" className="account-info" aria-label={label} />}>
        <Info aria-hidden />
      </PopoverTrigger>
      <PopoverContent align="start" className="account-info-body w-80 max-w-[calc(100vw-2rem)] p-3 text-[0.8125rem]">
        {children}
      </PopoverContent>
    </Popover>
  );
}
