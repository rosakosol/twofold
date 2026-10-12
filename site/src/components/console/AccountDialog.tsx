"use client";

import type { ReactElement, ReactNode } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";

/**
 * The dialog every write on the account page opens: a title, what it will do, the fields, and the
 * buttons. The rules that keep these safe (a reason, sometimes a typed confirmation) live in each
 * caller's `canSubmit`, exactly as they did when these were open forms; the dialog only refuses to
 * submit or close while a call is in flight.
 *
 * A real form, so Enter in the confirmation field submits once it is allowed to and not before:
 * a form does not submit implicitly through a disabled submit button, and `onSubmit` checks again.
 */
export function ActionDialog({
  open,
  onOpenChange,
  busy,
  trigger,
  triggerLabel,
  title,
  description,
  children,
  canSubmit,
  onSubmit,
  actions,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  busy: boolean;
  /** The button on the page, as an element (a `<Button>` with its variant and size). */
  trigger: ReactElement;
  triggerLabel: ReactNode;
  title: ReactNode;
  /** What this does, in full. Block content is fine; it renders in a div. */
  description?: ReactNode;
  children?: ReactNode;
  canSubmit: boolean;
  onSubmit: () => void;
  /** The footer's buttons after Cancel; the submit button among them is `type="submit"`. */
  actions: ReactNode;
}) {
  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        if (!busy) onOpenChange(next);
      }}
    >
      <DialogTrigger render={trigger}>{triggerLabel}</DialogTrigger>
      <DialogContent className="max-h-[calc(100dvh-2rem)] overflow-y-auto sm:max-w-lg">
        <form
          className="grid gap-4"
          onSubmit={(e) => {
            e.preventDefault();
            if (canSubmit && !busy) onSubmit();
          }}
        >
          <DialogHeader className="pr-8">
            <DialogTitle className="text-lg leading-snug font-bold">{title}</DialogTitle>
            {description && (
              <DialogDescription render={<div />} className="space-y-2 leading-relaxed">
                {description}
              </DialogDescription>
            )}
          </DialogHeader>
          {children}
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="ghost" disabled={busy} />}>Cancel</DialogClose>
            {actions}
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

/** The reason every action requires. Three characters is the floor the buttons check. */
export function ReasonField({
  id,
  value,
  onChange,
  disabled,
  placeholder = "Why this is being done, and who asked.",
}: {
  id: string;
  value: string;
  onChange: (v: string) => void;
  disabled: boolean;
  placeholder?: string;
}) {
  return (
    <div className="space-y-1.5">
      <Label htmlFor={id}>Reason</Label>
      <Textarea
        id={id}
        rows={2}
        placeholder={placeholder}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        disabled={disabled}
      />
    </div>
  );
}

/** Type-to-confirm: the specific thing (a name, an email) rather than "are you sure". */
export function ConfirmField({
  id,
  expected,
  value,
  onChange,
  disabled,
}: {
  id: string;
  /** What to show as the thing to type. */
  expected: ReactNode;
  value: string;
  onChange: (v: string) => void;
  disabled: boolean;
}) {
  return (
    <div className="space-y-1.5">
      <Label htmlFor={id} className="flex-wrap">
        Type <span className="font-mono break-all">{expected}</span> to confirm
      </Label>
      <Input
        id={id}
        autoComplete="off"
        spellCheck={false}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        disabled={disabled}
      />
    </div>
  );
}

/** The solid red button that does the destructive thing, inside its dialog. Same pairing as
 *  .btn-danger: --on-accent text, which is white in light mode and ink on the dark mode's pink. */
// `bg-none` drops the default variant's gradient, which is a background-image and would otherwise
// paint over the red.
export const DANGER_SUBMIT = "bg-none bg-destructive text-[color:var(--on-accent)] hover:brightness-105";
