"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Loader2, ShieldCheck, ShieldAlert } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { createClient } from "@/lib/supabase/client";
import { describeMfaError } from "@/lib/auth/mfa";
import { shortDate } from "@/lib/console/format";
import { AccountCard, ActionRow } from "@/components/console/AccountLayout";
import { ActionDialog } from "@/components/console/AccountDialog";
import { ConsoleError } from "@/components/console/ConsoleUI";
import { MfaEnrol, reloadInto } from "@/components/console/MfaForms";

const HERE = "/admin/security";

/**
 * An admin's own authenticators: whether MFA is on, adding a backup, removing one.
 *
 * Removing needs aal2, which Supabase enforces rather than this page. Reaching here with a factor
 * means the console door already took a code, so it only refuses if the session has since changed.
 */
export function MfaSecurity() {
  const { data, isLoading, error, refetch } = useQuery({
    queryKey: ["auth", "mfa_factors"],
    queryFn: async () => {
      const { data: factors, error: listError } = await createClient().auth.mfa.listFactors();
      if (listError) throw listError;
      return factors.totp;
    },
  });
  const [adding, setAdding] = useState(false);

  if (isLoading) return <Skeleton className="h-40 w-full rounded-2xl" />;
  if (error || !data) {
    return <ConsoleError title="Couldn't load your authenticators" onRetry={() => refetch()} />;
  }

  const on = data.length > 0;

  return (
    <div className="mfa-security">
      <p className={`mfa-status${on ? " is-on" : ""}`}>
        {on ? <ShieldCheck aria-hidden /> : <ShieldAlert aria-hidden />}
        {on
          ? `Two-step sign-in is on, with ${data.length === 1 ? "one authenticator" : `${data.length} authenticators`}.`
          : "Two-step sign-in is off. Your password alone opens this console."}
      </p>

      <AccountCard
        title="Authenticators"
        description={
          data.length === 1
            ? "There are no recovery codes, so add a backup on a second device. If you lose your only one, the account owner has to remove it in Supabase."
            : on
              ? undefined
              : "Add an authenticator app. There are no recovery codes, so add a backup on a second device as well."
        }
      >
        {on && (
          <ul className="account-actions">
            {data.map((factor) => (
              <RemoveFactorRow
                key={factor.id}
                id={factor.id}
                name={factor.friendly_name || "Authenticator"}
                addedAt={factor.created_at}
                isLast={data.length === 1}
              />
            ))}
          </ul>
        )}
        <div className="mfa-add">
          {adding || !on ? (
            <MfaEnrol
              // A first factor raises the session to aal2; a document load picks up the new level.
              onDone={() => reloadInto(HERE)}
              onCancel={on ? () => setAdding(false) : undefined}
            />
          ) : (
            <Button type="button" variant="outline" onClick={() => setAdding(true)}>
              Add a backup authenticator
            </Button>
          )}
        </div>
      </AccountCard>
    </div>
  );
}

function RemoveFactorRow({
  id,
  name,
  addedAt,
  isLast,
}: {
  id: string;
  name: string;
  addedAt: string;
  isLast: boolean;
}) {
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function remove() {
    setBusy(true);
    setError(null);
    const supabase = createClient();
    const { error: removeError } = await supabase.auth.mfa.unenroll({ factorId: id });
    if (removeError) {
      setBusy(false);
      setError(describeMfaError(removeError, "Couldn't remove that. Try again."));
      return;
    }
    // The token still says aal2 until it is refreshed, which would let the door wave through a
    // session with nothing behind it.
    await supabase.auth.refreshSession();
    reloadInto(HERE);
  }

  return (
    <ActionRow title={name} description={`Added ${shortDate(addedAt)}`}>
      <ActionDialog
        open={open}
        onOpenChange={setOpen}
        busy={busy}
        trigger={<Button type="button" variant="ghost" size="sm" />}
        triggerLabel="Remove"
        title={`Remove ${name}?`}
        description={
          isLast
            ? "This is your only authenticator. Removing it turns two-step sign-in off, and you will have to set one up again to use the console."
            : "Codes from this authenticator will stop working. If it is the one you last signed in with, you will be asked for a code from another."
        }
        canSubmit={!busy}
        onSubmit={remove}
        actions={
          <Button type="submit" variant="destructive" disabled={busy}>
            {busy && <Loader2 className="animate-spin" />}
            Remove
          </Button>
        }
      >
        {error && (
          <p className="mfa-error" role="alert">
            {error}
          </p>
        )}
      </ActionDialog>
    </ActionRow>
  );
}
