"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { KeyRound, Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { createClient } from "@/lib/supabase/client";
import { requestPasswordReset } from "@/lib/marketing/auth";
import { AccountSection, ActionRow } from "@/components/console/AccountLayout";
import { ActionDialog, ReasonField } from "@/components/console/AccountDialog";
import { InfoTip } from "@/components/console/InfoTip";

/**
 * Getting somebody back in: the standard password reset email, sent to the address on the account.
 *
 * Its own section rather than a grant or a danger-zone row, because it is neither: nothing is given
 * and nothing is taken away. It is the public "Forgot password?" form, pressed on their behalf, and
 * the console never sees or sets the password - they choose it at /auth/reset-password like anybody
 * else who asked.
 *
 * `admin_prepare_password_reset` reads the address server-side and records the entry before handing
 * it back, so the email cannot be aimed anywhere but the account's own address, and there is no
 * send without an entry. The send is then the same `requestPasswordReset` the site's own form uses,
 * with the same redirect, so a console-sent link behaves exactly like a self-service one.
 */
export function AccountSignIn({
  profileId,
  email,
  providers,
  deleted,
}: {
  profileId: string;
  email: string | null;
  /** `auth.identities` providers: "email", "apple", "google". */
  providers: string[];
  deleted: boolean;
}) {
  const router = useRouter();

  return (
    <AccountSection
      id="sign-in"
      title="Sign-in"
      icon={<KeyRound aria-hidden className="text-muted-foreground" />}
      description="Recorded with the reason you give."
    >
      <div className="account-card">
        <ul className="account-actions">
          <PasswordReset
            profileId={profileId}
            email={email}
            providers={providers}
            deleted={deleted}
            onDone={() => router.refresh()}
          />
        </ul>
      </div>
    </AccountSection>
  );
}

function PasswordReset({
  profileId,
  email,
  providers,
  deleted,
  onDone,
}: {
  profileId: string;
  email: string | null;
  providers: string[];
  deleted: boolean;
  onDone: () => void;
}) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  const [acknowledged, setAcknowledged] = useState(false);
  const [busy, setBusy] = useState(false);

  // No email identity means no password: Apple or Google only. The link would add one.
  const hasPassword = providers.includes("email");
  const others = providers.filter((p) => p !== "email").map(providerName);
  const othersLabel = others.join(" and ") || "another method";
  const relayAddress = Boolean(email?.toLowerCase().endsWith("@privaterelay.appleid.com"));
  const canSubmit = reason.trim().length >= 3 && (hasPassword || acknowledged);

  function reset() {
    setReason("");
    setAcknowledged(false);
  }

  async function run() {
    setBusy(true);
    const supabase = createClient();
    // The address comes back from the server, never from this page: the RPC reads it from
    // auth.users and records the entry before returning it. If it refuses, nothing is sent.
    const { data: address, error } = await supabase.rpc("admin_prepare_password_reset", {
      p_profile_id: profileId,
      p_reason: reason,
      p_acknowledge_adds_password: !hasPassword && acknowledged,
    });
    if (error || !address) {
      setBusy(false);
      toast.error(error?.message ?? "Couldn't prepare that reset.");
      return;
    }

    try {
      await requestPasswordReset(address);
    } catch (err) {
      setBusy(false);
      // The entry exists and says "requested", which is true. Most often this is Supabase's
      // one-a-minute limit per address, and its own message says how long to wait. The dialog stays
      // open so a retry is one click, and the page refreshes so the entry is visible.
      const message = (err instanceof Error && err.message.trim()) || "The email service refused it.";
      toast.error(`No email was sent: ${message.replace(/\.?$/, ".")} The attempt is in Admin history.`);
      onDone();
      return;
    }

    setBusy(false);
    toast.success(`Reset email sent to ${address}.`);
    reset();
    setOpen(false);
    onDone();
  }

  if (deleted) {
    return (
      <ActionRow
        title="Password reset email"
        description="Deleted. Sign-in is permanently disabled, so there is nothing to reset."
      />
    );
  }

  if (!email) {
    return <ActionRow title="Password reset email" description="There is no email address on this account to send it to." />;
  }

  return (
    <ActionRow
      title="Password reset email"
      info={
        <InfoTip label="How a console-sent reset works">
          <p>
            It is the same email as &quot;Forgot password?&quot;, sent to the address on the account.
            You never see or set the password; they choose it from the link.
          </p>
          <p>
            Supabase allows about one a minute per address. If the email does not arrive, check
            spam before sending another.
          </p>
          {!hasPassword && (
            <p>
              They sign in with {othersLabel}, so they have no password yet. Choosing one through the
              link adds email and password as another way in; {othersLabel} keeps working.
            </p>
          )}
        </InfoTip>
      }
      description={
        hasPassword
          ? "Emails them a link to choose a new password."
          : `Signs in with ${othersLabel} only. A reset would add a password.`
      }
      value={hasPassword ? undefined : <span className="muted">No password</span>}
    >
      <ActionDialog
        open={open}
        onOpenChange={(next) => {
          setOpen(next);
          if (!next) reset();
        }}
        busy={busy}
        trigger={<Button variant="outline" size="sm" />}
        triggerLabel="Send…"
        title={
          <>
            Send a password reset email to <span className="[overflow-wrap:anywhere]">{email}</span>?
          </>
        }
        description={
          <ul className="account-dialog-list">
            <li>The link lets them choose a new password. It works once and expires after an hour.</li>
            {!hasPassword && (
              // Plain emphasis, not .is-alert: it is a consequence to read, not a danger.
              <li className="font-medium text-foreground">
                This account signs in with {othersLabel} and has no password. Choosing one adds email
                and password as a second way in.
              </li>
            )}
            {relayAddress && (
              <li>
                This is an Apple &quot;Hide My Email&quot; address. Apple forwards it only from senders
                registered with them, so check it arrived.
              </li>
            )}
          </ul>
        }
        canSubmit={canSubmit}
        onSubmit={run}
        actions={
          <Button type="submit" disabled={busy || !canSubmit}>
            {busy && <Loader2 className="h-4 w-4 animate-spin" />}
            Send reset email
          </Button>
        }
      >
        {!hasPassword && (
          <label htmlFor="password-reset-ack" className="flex items-start gap-2 text-sm">
            <input
              id="password-reset-ack"
              type="checkbox"
              className="mt-0.5 size-4 flex-none accent-[color:var(--accent)]"
              checked={acknowledged}
              onChange={(e) => setAcknowledged(e.target.checked)}
              disabled={busy}
            />
            <span>I understand this adds a password to an account that signs in with {othersLabel}.</span>
          </label>
        )}
        <ReasonField
          id="password-reset-reason"
          value={reason}
          onChange={setReason}
          disabled={busy}
          placeholder="Why, and who asked. Ideally from the account's own address."
        />
      </ActionDialog>
    </ActionRow>
  );
}

/** "apple" -> "Apple". The providers arrive as Supabase's lowercase ids. */
function providerName(id: string): string {
  return id.charAt(0).toUpperCase() + id.slice(1);
}
