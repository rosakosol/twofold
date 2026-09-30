"use client";

import { useState } from "react";
import {
  isExistingAccountError,
  signInWithPassword,
  signUpWithPassword,
} from "@/lib/marketing/auth";
import { isAcceptablePassword } from "@/lib/marketing/passwordStrength";
import { nameError } from "@/lib/marketing/nameValidator";
import { PasswordStrengthMeter } from "@/components/marketing/PasswordStrengthMeter";

export type EmailPasswordMode = "create" | "signin";

/**
 * Each route group's own input and submit elements.
 *
 * The two places this form renders have deliberately different design systems — (marketing)
 * dresses bare elements with marketing.css, (board) uses shadcn — so what is shared here is the
 * field set, the validation and the error mapping, not a look. Dragging either system into the
 * other's half of the app is the one thing this extraction must not do, hence the slots.
 *
 * Everything this file styles itself is inline and system-neutral, the same compromise
 * PasswordStrengthMeter already makes so that /auth/reset-password in (board) can render it.
 */
export interface EmailPasswordFormChrome {
  /** The `<form>` element. Marketing passes `auth-form`, which owns both the stacking and the
   *  field treatment (see marketing.css) — which is why `Field` can be left out there. */
  form?: string;
  Field?: React.ComponentType<React.ComponentProps<"input">>;
  Submit?: React.ComponentType<React.ComponentProps<"button">>;
}

interface EmailPasswordFormProps {
  mode: EmailPasswordMode;
  /**
   * Called when the form itself changes mode — it flips to `signin` when a signup turns out to be
   * for an address that already has an account. The "already have an account?" switch is the
   * caller's, because that control is pure chrome and each group writes it in its own idiom.
   */
  onModeChange: (mode: EmailPasswordMode) => void;
  /** Submit-time failures, and `null` to clear. Reported rather than rendered: on /pricing the
   *  same line carries the Apple/Google failures too, so a form that rendered its own would put
   *  two error paragraphs in one card. */
  onError: (message: string | null) => void;
  /**
   * Runs once Supabase has accepted the credentials and a session exists.
   *
   * Optional, and /pricing deliberately does not pass it: that page resumes its interrupted
   * purchase from `onAuthChange` instead, which is the path an email/password sign-in actually
   * takes (it changes the session in place, without the reload the provider redirects cause). See
   * `resumePendingPurchase` — it is reachable from both places a session can arrive and claims the
   * pending plan synchronously precisely so one sign-in cannot start two checkouts.
   */
  onSuccess?: () => void;
  chrome?: EmailPasswordFormChrome;
}

/**
 * The email-and-password half of signing up and signing in, shared by /pricing's checkout step and
 * /auth/sign-in.
 *
 * It started life inside PricingClient. The rules it enforces are not local to that page: they
 * mirror `CreateAccountView.canContinue` and `SaveAccountView.canContinueWithEmail` field for
 * field, because an account the iOS app would refuse to create must not be creatable on the web
 * either — two surfaces disagreeing about what a valid account is means somebody signs up here and
 * then cannot get in over there. One copy, so the two cannot drift.
 */
export function EmailPasswordForm({
  mode,
  onModeChange,
  onError,
  onSuccess,
  chrome,
}: EmailPasswordFormProps) {
  const Field = chrome?.Field ?? "input";
  const Submit = chrome?.Submit ?? "button";

  const [firstName, setFirstName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [acceptedTerms, setAcceptedTerms] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  // Shown under the field as well as gating the button — see passwordStrength.ts on why a stricter
  // rule has to explain itself. The password's own reason is rendered by PasswordStrengthMeter.
  const nameProblem = firstName.trim() === "" ? null : nameError(firstName);

  const canSubmit =
    mode === "signin"
      ? email.trim() !== "" && password !== ""
      : nameError(firstName) === null &&
        email.trim() !== "" &&
        confirmPassword === password &&
        isAcceptablePassword(password, firstName, email) &&
        acceptedTerms;

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (!canSubmit || submitting) return;
    onError(null);
    setSubmitting(true);

    try {
      if (mode === "signin") {
        await signInWithPassword(email, password);
      } else {
        const data = await signUpWithPassword(firstName, email, password);
        // Supabase can report an existing address as a success carrying a user with no identities,
        // rather than as an error — see isExistingAccountError. Treated the same either way: send
        // them to sign in rather than leaving them on a form that appeared to work.
        if (isExistingAccountError(null, data)) {
          onModeChange("signin");
          onError("An account with this email already exists. Sign in to use it.");
          setSubmitting(false);
          return;
        }
      }
      onSuccess?.();
    } catch (err) {
      if (mode === "create" && isExistingAccountError(err)) {
        onModeChange("signin");
        onError("An account with this email already exists. Sign in to use it.");
      } else if (mode === "signin") {
        onError("That email and password didn't match an account. Please try again.");
      } else {
        onError("We couldn't create your account. Please try again.");
      }
    }
    setSubmitting(false);
  }

  return (
    <form className={chrome?.form} onSubmit={submit} noValidate>
      {mode === "create" && (
        <>
          <label className="sr-only" htmlFor="signup-first-name">
            First name
          </label>
          <Field
            id="signup-first-name"
            name="given-name"
            type="text"
            autoComplete="given-name"
            placeholder="First name"
            value={firstName}
            onChange={(event) => setFirstName(event.target.value)}
          />
          {nameProblem && <p style={{ fontSize: "0.85em", opacity: 0.8 }}>{nameProblem}</p>}
        </>
      )}

      <label className="sr-only" htmlFor="signup-email">
        Email address
      </label>
      <Field
        id="signup-email"
        name="email"
        type="email"
        inputMode="email"
        autoComplete="email"
        placeholder="yourname@email.com"
        value={email}
        onChange={(event) => setEmail(event.target.value)}
      />

      <label className="sr-only" htmlFor="signup-password">
        Password
      </label>
      <Field
        id="signup-password"
        name="password"
        type="password"
        autoComplete={mode === "create" ? "new-password" : "current-password"}
        placeholder="Password"
        value={password}
        onChange={(event) => setPassword(event.target.value)}
      />

      {mode === "create" && (
        <>
          <label className="sr-only" htmlFor="signup-confirm">
            Confirm password
          </label>
          <Field
            id="signup-confirm"
            name="confirm-password"
            type="password"
            autoComplete="new-password"
            placeholder="Confirm password"
            value={confirmPassword}
            onChange={(event) => setConfirmPassword(event.target.value)}
          />

          {/* Says which rule is unmet rather than only disabling the button, because a
              dead button with no reason is the same dead end as no button. */}
          <PasswordStrengthMeter password={password} name={firstName} email={email} />
          {confirmPassword !== "" && confirmPassword !== password && (
            <p style={{ fontSize: "0.85em", opacity: 0.8, marginBottom: 8 }}>
              Those passwords don&apos;t match.
            </p>
          )}

          {/* The same gate the app puts on every route off SaveAccountView, and the same
              sentence, so the thing being agreed to does not depend on where you signed
              up. A bare checkbox and inline layout rather than either group's own control:
              this is the one field both design systems have to render identically. */}
          <label
            style={{
              display: "flex",
              gap: 8,
              alignItems: "flex-start",
              fontSize: "0.85em",
              marginBottom: 16,
            }}
          >
            <input
              type="checkbox"
              checked={acceptedTerms}
              onChange={(event) => setAcceptedTerms(event.target.checked)}
              style={{ marginTop: 3 }}
            />
            <span>
              I&apos;m 16 or over, and I agree to the <a href="/terms">Terms of Use</a> and{" "}
              <a href="/privacy">Privacy Policy</a>.
            </span>
          </label>
        </>
      )}

      <Submit type="submit" disabled={!canSubmit || submitting}>
        {submitting ? "One moment…" : mode === "create" ? "Create account" : "Sign in"}
      </Submit>
    </form>
  );
}
