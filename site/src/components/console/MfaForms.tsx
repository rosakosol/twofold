"use client";

import { useEffect, useState } from "react";
import { Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { createClient } from "@/lib/supabase/client";
import { signOutAndGoHome } from "@/lib/auth/signOutAndGoHome";
import { describeMfaError, nextFactorName, normaliseTotpCode, totpQrImageSrc } from "@/lib/auth/mfa";

/**
 * Going somewhere once the session has changed level, with a full document load for the reason
 * signOutAndGoHome gives: every server-rendered view and cached role answer was for the old session.
 * `mfa.verify` has already written the aal2 session to the cookies by now, so the load carries it.
 */
export function reloadInto(path: string) {
  window.location.assign(path);
}

function TotpCodeField({
  id,
  value,
  onChange,
  disabled,
  autoFocus,
}: {
  id: string;
  value: string;
  onChange: (value: string) => void;
  disabled: boolean;
  autoFocus?: boolean;
}) {
  return (
    <div className="space-y-1.5">
      <Label htmlFor={id}>6-digit code</Label>
      <Input
        id={id}
        className="mfa-code"
        inputMode="numeric"
        autoComplete="one-time-code"
        placeholder="000000"
        autoFocus={autoFocus}
        value={value}
        onChange={(e) => onChange(normaliseTotpCode(e.target.value))}
        disabled={disabled}
      />
    </div>
  );
}

function MfaError({ message }: { message: string | null }) {
  if (!message) return null;
  return (
    <p className="mfa-error" role="alert">
      {message}
    </p>
  );
}

/** Reaching aal2: a code from a factor already enrolled. Works at aal1 by definition. */
export function MfaChallenge({ next }: { next: string }) {
  const [factors, setFactors] = useState<{ id: string; friendly_name?: string }[] | null>(null);
  const [factorId, setFactorId] = useState<string | null>(null);
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    createClient()
      .auth.mfa.listFactors()
      .then(({ data, error: listError }) => {
        if (cancelled) return;
        if (listError || !data) {
          setError(describeMfaError(listError, "Couldn't load your authenticators. Reload the page to try again."));
          return;
        }
        setFactors(data.totp);
        setFactorId(data.totp[0]?.id ?? null);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!factorId || code.length !== 6 || busy) return;
    setBusy(true);
    setError(null);
    const { error: verifyError } = await createClient().auth.mfa.challengeAndVerify({ factorId, code });
    if (verifyError) {
      setBusy(false);
      setCode("");
      setError(describeMfaError(verifyError, "Couldn't check that code. Try again."));
      return;
    }
    reloadInto(next);
  }

  return (
    <div className="account-card mfa-card">
      <h1>Enter your code</h1>
      <p className="mfa-lede">Open your authenticator app and enter the current code for Twofold.</p>
      <form className="mfa-form" onSubmit={submit}>
        {factors && factors.length > 1 && (
          <fieldset className="mfa-factor-choice">
            <legend>Authenticator</legend>
            {factors.map((factor) => (
              <label key={factor.id}>
                <input
                  type="radio"
                  name="factor"
                  checked={factorId === factor.id}
                  onChange={() => setFactorId(factor.id)}
                  disabled={busy}
                />
                {factor.friendly_name || "Authenticator"}
              </label>
            ))}
          </fieldset>
        )}
        <TotpCodeField id="mfa-code" value={code} onChange={setCode} disabled={busy || !factorId} autoFocus />
        <MfaError message={error} />
        <Button type="submit" disabled={busy || !factorId || code.length !== 6}>
          {busy && <Loader2 className="animate-spin" />}
          Continue
        </Button>
      </form>
      <p className="mfa-foot">
        Lost your authenticator? Ask the account owner to remove it in Supabase, then sign in again.{" "}
        <button type="button" className="mfa-link" onClick={() => signOutAndGoHome()}>
          Sign out
        </button>
      </p>
    </div>
  );
}

/**
 * Adding a factor: the first one at aal1, or another one at aal2 (Supabase refuses an aal1 session
 * that already has a verified factor, so a stolen password cannot add its own).
 *
 * Started by a button rather than on mount because each start creates a factor in Supabase, which
 * would otherwise mean one for every page view. Whatever an earlier abandoned attempt left behind is
 * removed first: it would count against the limit, and could hold the name this one needs.
 */
export function MfaEnrol({
  onDone,
  onCancel,
  startLabel = "Set up an authenticator",
}: {
  onDone: () => void;
  onCancel?: () => void;
  startLabel?: string;
}) {
  const [enrolment, setEnrolment] = useState<{ factorId: string; qr: string; secret: string } | null>(null);
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function start() {
    setBusy(true);
    setError(null);
    const supabase = createClient();
    const { data: factors, error: listError } = await supabase.auth.mfa.listFactors();
    if (listError || !factors) {
      setBusy(false);
      setError(describeMfaError(listError, "Couldn't start that. Try again."));
      return;
    }
    await Promise.all(
      factors.all
        .filter((factor) => factor.status === "unverified")
        .map((factor) => supabase.auth.mfa.unenroll({ factorId: factor.id })),
    );
    const { data, error: enrolError } = await supabase.auth.mfa.enroll({
      factorType: "totp",
      issuer: "Twofold",
      friendlyName: nextFactorName(factors.totp.map((factor) => factor.friendly_name)),
    });
    setBusy(false);
    if (enrolError || !data) {
      setError(describeMfaError(enrolError, "Couldn't start that. Try again."));
      return;
    }
    setEnrolment({ factorId: data.id, qr: totpQrImageSrc(data.totp.qr_code), secret: data.totp.secret });
  }

  async function verify(e: React.FormEvent) {
    e.preventDefault();
    if (!enrolment || code.length !== 6 || busy) return;
    setBusy(true);
    setError(null);
    const { error: verifyError } = await createClient().auth.mfa.challengeAndVerify({
      factorId: enrolment.factorId,
      code,
    });
    if (verifyError) {
      setBusy(false);
      setCode("");
      setError(describeMfaError(verifyError, "Couldn't check that code. Try again."));
      return;
    }
    onDone();
  }

  async function cancel() {
    if (enrolment) {
      setBusy(true);
      await createClient().auth.mfa.unenroll({ factorId: enrolment.factorId });
      setBusy(false);
      setEnrolment(null);
      setCode("");
      setError(null);
    }
    onCancel?.();
  }

  if (!enrolment) {
    return (
      <div className="mfa-form">
        <MfaError message={error} />
        <div className="mfa-actions">
          <Button type="button" onClick={start} disabled={busy}>
            {busy && <Loader2 className="animate-spin" />}
            {startLabel}
          </Button>
          {onCancel && (
            <Button type="button" variant="ghost" onClick={onCancel} disabled={busy}>
              Cancel
            </Button>
          )}
        </div>
      </div>
    );
  }

  return (
    <form className="mfa-form" onSubmit={verify}>
      <div className="mfa-enrol">
        {/* eslint-disable-next-line @next/next/no-img-element -- a local data URI, not something to optimise */}
        <img className="mfa-qr" src={enrolment.qr} alt="QR code for your authenticator app" width={176} height={176} />
        <div className="mfa-enrol-steps">
          <p>Scan this with an authenticator app, such as 1Password, Authy or Google Authenticator.</p>
          <p className="mfa-secret-label">Can&apos;t scan it? Enter this key instead:</p>
          <code className="mfa-secret">{enrolment.secret}</code>
        </div>
      </div>
      <TotpCodeField id="mfa-enrol-code" value={code} onChange={setCode} disabled={busy} autoFocus />
      <MfaError message={error} />
      <div className="mfa-actions">
        <Button type="submit" disabled={busy || code.length !== 6}>
          {busy && <Loader2 className="animate-spin" />}
          Turn on
        </Button>
        <Button type="button" variant="ghost" onClick={cancel} disabled={busy}>
          Cancel
        </Button>
      </div>
    </form>
  );
}

/** The MFA page's enrol card. `required` once the data gate refuses this session without it. */
export function MfaEnrolCard({ next, required }: { next: string; required: boolean }) {
  return (
    <div className="account-card mfa-card">
      <h1>Protect your admin account</h1>
      <p className="mfa-lede">
        {required
          ? "The console needs a code from an authenticator app as well as your password. Set one up to continue."
          : "Add a code from an authenticator app to your sign-in. The console will soon require it."}
      </p>
      <MfaEnrol onDone={() => reloadInto(next)} />
      <p className="mfa-foot">
        There are no recovery codes, so add a second authenticator as a backup once you are in.{" "}
        {required ? (
          <button type="button" className="mfa-link" onClick={() => signOutAndGoHome()}>
            Sign out
          </button>
        ) : (
          <a className="mfa-link" href={next}>
            Not now
          </a>
        )}
      </p>
    </div>
  );
}
