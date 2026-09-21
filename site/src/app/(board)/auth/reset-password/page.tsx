"use client";

import { Suspense, useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { createClient } from "@/lib/supabase/client";
import { Loader2, CheckCircle2 } from "lucide-react";

/**
 * Where a password-recovery email lands.
 *
 * Until now the app asked Supabase to send people to `twofold://reset-password`
 * (BackendService.requestPasswordReset). Two things went wrong with that:
 *
 *   1. A `redirect_to` that is not on the project's Redirect URLs allow-list is not rejected —
 *      Supabase silently substitutes the project's Site URL instead. So the link "worked" and
 *      dropped everyone on the marketing site with no explanation, which is the bug this fixes.
 *
 *   2. A custom scheme means nothing in a desktop browser. Even correctly allow-listed, anyone
 *      who opened the email on a laptop had nowhere to go. No allow-list entry fixes that.
 *
 * So recovery now points at this page, an ordinary HTTPS URL. On an iOS device with the app
 * installed it is a Universal Link (see the AASA route) and iOS opens Twofold instead of Safari,
 * where `OnboardingCoordinatorView` handles it exactly as before. Everywhere else — desktop, a
 * browser on a phone without the app — this page renders.
 *
 * ---------------------------------------------------------------------------
 * Why verifyOtp and not exchangeCodeForSession
 * ---------------------------------------------------------------------------
 *
 * /auth/callback exchanges a PKCE `code`, and that is right for sign-in because the same browser
 * that started the flow finishes it, so the code verifier is in its cookie jar.
 *
 * Recovery is different: the flow is very often started somewhere else. Someone taps "forgot
 * password" in the app on their phone and opens the email on their laptop — and the laptop has no
 * verifier, so a code exchange fails with "code verifier not found in storage" for a link that is
 * perfectly valid. `verifyOtp` with the emailed `token_hash` carries everything needed in the link
 * itself, so it works from any device. That is the whole reason this page does not reuse the
 * callback route.
 */
export default function ResetPasswordPage() {
  return (
    <Suspense>
      <ResetPasswordForm />
    </Suspense>
  );
}

type Stage = "verifying" | "ready" | "saving" | "done" | "invalid";

export function passwordProblem(password: string, confirmation: string): string | null {
  // Mirrors the app's own ResetPasswordView so the same password is accepted in both places, and
  // matches config.toml's `minimum_password_length`. A rule enforced here but not there (or the
  // other way round) shows up as a password that works on one device and not the other.
  if (password.length < 6) return "Use at least 6 characters.";
  if (password !== confirmation) return "Those two passwords don't match.";
  return null;
}

function ResetPasswordForm() {
  const searchParams = useSearchParams();

  const [stage, setStage] = useState<Stage>("verifying");
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [errorMessage, setErrorMessage] = useState("");

  // Supabase sends `token_hash` + `type` on the modern link shape. Older projects (and older
  // emails still sitting in inboxes) use an implicit-grant fragment instead, which the client
  // picks up on its own when it loads — so a missing token_hash is not automatically a dead link,
  // and this checks for a session before giving up.
  const tokenHash = searchParams.get("token_hash");
  const type = searchParams.get("type");

  useEffect(() => {
    let cancelled = false;

    async function verify() {
      const supabase = createClient();

      if (tokenHash) {
        const { error } = await supabase.auth.verifyOtp({
          token_hash: tokenHash,
          type: type === "invite" ? "invite" : "recovery",
        });
        if (cancelled) return;
        if (error) {
          setStage("invalid");
          setErrorMessage(error.message);
          return;
        }
        setStage("ready");
        return;
      }

      // No token_hash: either an older fragment-style link the client has already consumed into a
      // session, or somebody navigating here directly.
      const { data } = await supabase.auth.getSession();
      if (cancelled) return;
      setStage(data.session ? "ready" : "invalid");
    }

    verify();
    return () => {
      cancelled = true;
    };
  }, [tokenHash, type]);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();

    const problem = passwordProblem(password, confirmation);
    if (problem) {
      setErrorMessage(problem);
      return;
    }

    setStage("saving");
    setErrorMessage("");

    const supabase = createClient();
    const { error } = await supabase.auth.updateUser({ password });

    if (error) {
      setStage("ready");
      setErrorMessage(error.message);
      return;
    }

    // Deliberately signed out afterwards. The recovery link granted a real session, and leaving it
    // live would mean a forwarded email still holds one after the password has changed — the thing
    // resetting a password is supposed to end. The app's ResetPasswordView does the same.
    await supabase.auth.signOut();
    setStage("done");
  }

  if (stage === "verifying") {
    return (
      <Shell title="Checking your link">
        <div className="flex items-center gap-2 text-sm text-muted-foreground">
          <Loader2 className="h-4 w-4 animate-spin" />
          One moment…
        </div>
      </Shell>
    );
  }

  if (stage === "invalid") {
    return (
      <Shell
        title="This link has expired"
        description="Password reset links can only be used once, and they don't last long."
      >
        <p className="text-sm text-muted-foreground">
          Request a new one from the sign-in screen in Twofold, and open it as soon as it arrives.
        </p>
        {errorMessage && <p className="mt-3 text-sm text-muted-foreground">{errorMessage}</p>}
      </Shell>
    );
  }

  if (stage === "done") {
    return (
      <Shell title="Password changed">
        <div className="flex items-start gap-2 text-sm text-muted-foreground">
          <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0" />
          <p>You can sign in to Twofold with your new password now.</p>
        </div>
      </Shell>
    );
  }

  return (
    <Shell title="Choose a new password" description="This replaces the password on your Twofold account.">
      <form onSubmit={handleSubmit} className="space-y-4">
        <div className="space-y-1.5">
          <Label htmlFor="password">New password</Label>
          <Input
            id="password"
            type="password"
            autoComplete="new-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            disabled={stage === "saving"}
          />
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="confirmation">Confirm new password</Label>
          <Input
            id="confirmation"
            type="password"
            autoComplete="new-password"
            value={confirmation}
            onChange={(e) => setConfirmation(e.target.value)}
            disabled={stage === "saving"}
          />
        </div>

        {errorMessage && <p className="text-sm text-destructive">{errorMessage}</p>}

        <Button type="submit" disabled={stage === "saving"} className="w-full">
          {stage === "saving" && <Loader2 className="h-4 w-4 animate-spin" />}
          Change password
        </Button>
      </form>
    </Shell>
  );
}

function Shell({
  title,
  description,
  children,
}: {
  title: string;
  description?: string;
  children: React.ReactNode;
}) {
  return (
    <div className="mx-auto flex min-h-[60vh] max-w-md items-center px-4 py-10">
      <Card className="w-full">
        <CardHeader>
          <CardTitle>{title}</CardTitle>
          {description && <CardDescription>{description}</CardDescription>}
        </CardHeader>
        <CardContent>{children}</CardContent>
      </Card>
    </div>
  );
}
