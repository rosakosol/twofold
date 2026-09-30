"use client";

import { useState } from "react";
import { requestPasswordReset } from "@/lib/marketing/auth";

/**
 * Off, asking for the address, or confirming it was sent.
 *
 * A state of its own rather than a third `EmailPasswordMode`: that enum is shared with /pricing's
 * checkout, and widening it would put "I've forgotten my password" inside the mode that decides
 * whether a purchase creates an account or signs in to one.
 */
export type PasswordResetStage = "off" | "form" | "sent";

/**
 * The words, shared because these are the ones that must not drift.
 *
 * The confirmation never says whether that address had an account. Supabase is configured not to
 * confirm to a stranger which addresses are registered, and a form that answered "no such account"
 * would hand back exactly what that setting withholds — an oracle for testing whether somebody uses
 * Twofold. That is a property of the product, not of a page, so one surface cannot be allowed to
 * phrase it as "check your inbox" while the other is careful.
 *
 * Held here rather than in each card because both surfaces render the heading themselves: the
 * board's sits in a shadcn `CardHeader` and the marketing card's in its own `<h3>`, and neither can
 * be moved inside the panel without dragging one design system into the other's half of the app.
 */
export const passwordResetCopy = {
  title: "Reset your password",
  form: "We'll email you a link to set a new one. It works on any device - open it wherever you read your email.",
  sent: "If that address has an account, a link to set a new password is on its way.",
} as const;

/**
 * Each route group's own input and submit elements — the same slots, for the same reason, as
 * EmailPasswordFormChrome. (marketing) dresses bare elements with marketing.css and (board) uses
 * shadcn, so what is shared is the field, the call and the wording, not a look.
 */
export interface PasswordResetPanelChrome {
  form?: string;
  Field?: React.ComponentType<React.ComponentProps<"input">>;
  Submit?: React.ComponentType<React.ComponentProps<"button">>;
  /** The "back to sign in" control, which is a plain text link in both systems but not the same one. */
  BackLink?: React.ComponentType<React.ComponentProps<"button">>;
}

interface PasswordResetPanelProps {
  stage: "form" | "sent";
  onStageChange: (stage: PasswordResetStage) => void;
  /** Reported rather than rendered, because on both surfaces the same line already carries the
   *  OAuth and sign-in failures — a panel with its own would put two error paragraphs in one card. */
  onError: (message: string | null) => void;
  /**
   * Rendered in the sent state, under the confirmation. Deliberately the caller's: what to do next
   * genuinely differs. On the board the link is the whole journey; in the middle of a checkout the
   * tab still holds the plan that was picked, so coming back to it is the shortest way to finish.
   */
  sentNote?: React.ReactNode;
  /** What the submit button says while the request is in flight — the board threads a spinner in. */
  busyLabel?: React.ReactNode;
  chrome?: PasswordResetPanelChrome;
}

/**
 * Ask Supabase for a recovery email.
 *
 * Inline on whichever card the person is already looking at, rather than at a route of its own:
 * "forgot password" is a detour from signing in, and a separate page would need its own header, its
 * own way back and its own place in the nav for a form with one field in it. On /pricing it would
 * cost more than that — navigating away from a checkout abandons the plan the visitor picked, which
 * lives in this tab's sessionStorage.
 *
 * Shared by /auth/sign-in and /pricing's checkout step. The second was the gap: the web could send
 * a recovery email from the board and consume one at /auth/reset-password, but somebody signing in
 * to buy had no way to ask for one — and they are disproportionately the people who need it, since
 * an account exists from `.saveAccount` onwards, before the onboarding paywall anyone quits at.
 */
export function PasswordResetPanel({
  stage,
  onStageChange,
  onError,
  sentNote,
  busyLabel,
  chrome,
}: PasswordResetPanelProps) {
  const Field = chrome?.Field ?? "input";
  const Submit = chrome?.Submit ?? "button";
  const BackLink = chrome?.BackLink ?? "button";

  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(false);

  function back() {
    onStageChange("off");
    onError(null);
  }

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (busy || email.trim() === "") return;
    setBusy(true);
    onError(null);
    try {
      await requestPasswordReset(email);
      onStageChange("sent");
    } catch (err) {
      // Reported as-is rather than paraphrased. A rate limit is the likeliest failure here and says
      // something useful; this is also the path people reach already locked out, where a vague
      // message is what sends them to support instead.
      onError(err instanceof Error ? err.message : "Couldn't send that reset email.");
    }
    setBusy(false);
  }

  if (stage === "sent") {
    return (
      <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
        {sentNote}
        <BackLink type="button" onClick={back}>
          Back to sign in
        </BackLink>
      </div>
    );
  }

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
      <form className={chrome?.form} onSubmit={submit} noValidate>
        <Field
          type="email"
          inputMode="email"
          autoComplete="email"
          placeholder="you@email.com"
          aria-label="Email address"
          value={email}
          onChange={(event) => setEmail(event.target.value)}
        />
        <Submit type="submit" disabled={busy || email.trim() === ""}>
          {busy ? (busyLabel ?? "Send reset link") : "Send reset link"}
        </Submit>
      </form>
      <BackLink type="button" onClick={back}>
        Back to sign in
      </BackLink>
    </div>
  );
}
