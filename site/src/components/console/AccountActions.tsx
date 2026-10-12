"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Loader2, TriangleAlert } from "lucide-react";
import { Button } from "@/components/ui/button";
import { createClient } from "@/lib/supabase/client";
import { functionErrorMessage } from "@/lib/supabase/functionError";
import { cancellability } from "@/lib/console/accountDetail";
import { AccountSection, ActionRow } from "@/components/console/AccountLayout";
import { ActionDialog, ConfirmField, DANGER_SUBMIT, ReasonField } from "@/components/console/AccountDialog";
import { InfoTip } from "@/components/console/InfoTip";

/**
 * The console's write surface for one account: the danger zone at the bottom of the page.
 *
 * Everything here is something the account's owner could do themselves if they could sign in - and
 * that is the boundary. This console exists because they sometimes cannot: the app is refusing,
 * they have lost access to the address, or email is the only channel they have. It does not exist
 * to do things to people, so nothing here has a counterpart the owner lacks.
 *
 * Three rules, applied to every action:
 *
 *   1. A reason is required, and the submit stays disabled without one. Not because anybody reads
 *      them routinely, but because an unexplained destructive action found in the log in two years
 *      is indistinguishable from a mistake.
 *   2. The confirmation is typing something specific - the partner's name, the account's email -
 *      rather than pressing "are you sure". A second button is a reflex people clear without
 *      reading; typing cannot be done by accident.
 *   3. Nothing is offered that cannot actually be done. An App Store subscription shows why it is
 *      not cancellable here instead of a button that would report success for a charge that is
 *      still coming.
 *
 * Each action is a row with one line and a button; the full consequences, the reason and the typed
 * confirmation are in the dialog the button opens, where they are read at the moment they matter.
 */
export function AccountActions({
  profileId,
  email,
  alreadyDeleted,
  couple,
  subscriptionStore,
  subscriptionActive,
}: {
  profileId: string;
  email: string;
  alreadyDeleted: boolean;
  couple: { id: string; partnerFirstName: string | null } | null;
  subscriptionStore: string | null;
  subscriptionActive: boolean;
}) {
  const router = useRouter();
  const subscription = cancellability(subscriptionStore, subscriptionActive);

  return (
    <AccountSection id="danger" title="Danger zone" icon={<TriangleAlert aria-hidden />} className="account-danger">
      {alreadyDeleted ? (
        <p className="text-muted-foreground">
          Already deleted. Sign-in is permanently disabled and cannot be restored.
        </p>
      ) : (
        <>
          <p className="mb-2 text-muted-foreground">Each of these is recorded with the reason you give.</p>
          <ul className="account-actions">
            {subscriptionActive && (
              <CancelSubscription
                profileId={profileId}
                ours={subscription.ours}
                label={subscription.label}
                onDone={() => router.refresh()}
              />
            )}

            {couple && (
              <Disconnect
                profileId={profileId}
                coupleId={couple.id}
                partnerName={couple.partnerFirstName}
                onDone={() => router.refresh()}
              />
            )}

            <DeleteAccount
              profileId={profileId}
              email={email}
              storeManaged={subscriptionActive && !subscription.ours}
              onDone={() => router.refresh()}
            />
          </ul>
        </>
      )}
    </AccountSection>
  );
}

function CancelSubscription({
  profileId,
  ours,
  label,
  onDone,
}: {
  profileId: string;
  ours: boolean;
  label: string;
  onDone: () => void;
}) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const canSubmit = reason.trim().length >= 3;

  async function run() {
    setBusy(true);
    const supabase = createClient();
    const { data, error } = await supabase.functions.invoke("admin-actions", {
      body: { action: "subscription.cancel", profileId, reason },
    });
    setBusy(false);
    if (error || !data?.ok) {
      // The function's own refusal - "no web subscription", "not authorised", a RevenueCat error -
      // rather than one sentence covering all of them. It arrives on the error rather than in
      // `data`, which is null for every non-2xx; see functionErrorMessage.
      toast.error(await functionErrorMessage(error, "Couldn't cancel that subscription."));
      return;
    }
    // Zero is the App Store case reaching here anyway - reported plainly rather than as success,
    // so nobody tells a customer a charge has stopped when it has not.
    if (data.cancelled === 0) {
      toast.warning("Nothing was cancelled - no web subscription found on this account.");
    } else {
      toast.success("Cancelled. It won't renew; they keep it until the period they've paid for ends.");
    }
    setReason("");
    setOpen(false);
    onDone();
  }

  if (!ours) {
    return (
      <ActionRow
        title="Cancel subscription"
        info={
          <InfoTip label="Why this subscription can't be cancelled here">
            <p>
              Tell them to cancel it where they bought it. For an App Store subscription that is
              Settings &gt; Apple Account &gt; Subscriptions on their device; Apple gives us no way to
              do it for them.
            </p>
          </InfoTip>
        }
        description={`${label.charAt(0).toUpperCase()}${label.slice(1)}. They cancel it where they bought it.`}
      />
    );
  }

  return (
    <ActionRow title="Cancel subscription" description="Stops renewal. They keep what they've paid for.">
      <ActionDialog
        open={open}
        onOpenChange={(next) => {
          setOpen(next);
          if (!next) setReason("");
        }}
        busy={busy}
        trigger={<Button variant="outline" size="sm" />}
        triggerLabel="Cancel…"
        title="Cancel their subscription"
        description={
          <p>
            A website subscription. This stops the renewal; they keep the plan until the end of the
            period already paid for. Stripe refunds nothing, so ending it now would take time they
            bought.
          </p>
        }
        canSubmit={canSubmit}
        onSubmit={run}
        actions={
          <Button type="submit" variant="outline" disabled={busy || !canSubmit}>
            {busy && <Loader2 className="h-4 w-4 animate-spin" />}
            Cancel their subscription
          </Button>
        }
      >
        <ReasonField id="cancel-reason" value={reason} onChange={setReason} disabled={busy} />
      </ActionDialog>
    </ActionRow>
  );
}

function Disconnect({
  profileId,
  coupleId,
  partnerName,
  onDone,
}: {
  profileId: string;
  coupleId: string;
  partnerName: string | null;
  onDone: () => void;
}) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [busy, setBusy] = useState(false);
  const name = partnerName || "their partner";
  const expected = (partnerName || "").trim().toLowerCase();
  const confirmed = expected !== "" && confirmation.trim().toLowerCase() === expected;
  const canSubmit = confirmed && reason.trim().length >= 3;

  async function run() {
    setBusy(true);
    const supabase = createClient();
    // `p_on_behalf_of` is this account, not the admin. The couple row must record that THIS person
    // left - that is what the app reads, and it decides which partner gets the "your subscription
    // lapsed because they left" notice.
    const { error } = await supabase.rpc("admin_dissolve_couple", {
      p_couple_id: coupleId,
      p_on_behalf_of: profileId,
      p_reason: reason,
    });
    setBusy(false);
    if (error) {
      toast.error(error.message);
      return;
    }
    toast.success(`Disconnected. Their shared history is archived on the usual 90-day timer.`);
    setReason("");
    setConfirmation("");
    setOpen(false);
    onDone();
  }

  return (
    <ActionRow title={`Disconnect from ${name}`} description="Ends the couple as if they left. Shared history is archived.">
      <ActionDialog
        open={open}
        onOpenChange={(next) => {
          setOpen(next);
          if (!next) {
            setReason("");
            setConfirmation("");
          }
        }}
        busy={busy}
        trigger={<Button variant="destructive" size="sm" />}
        triggerLabel="Disconnect…"
        title={`Disconnect from ${name}?`}
        description={
          <ul className="account-dialog-list">
            <li>
              Done as this account, so the record shows they left. That decides who gets the
              subscription-lapse notice.
            </li>
            <li>
              Shared history is archived, not deleted, on the usual 90-day timer. Reconnecting before
              it runs out offers it back.
            </li>
          </ul>
        }
        canSubmit={canSubmit}
        onSubmit={run}
        actions={
          <Button type="submit" className={DANGER_SUBMIT} disabled={busy || !canSubmit}>
            {busy && <Loader2 className="h-4 w-4 animate-spin" />}
            Disconnect them
          </Button>
        }
      >
        <ReasonField id="disconnect-reason" value={reason} onChange={setReason} disabled={busy} />
        <ConfirmField
          id="disconnect-confirm"
          expected={partnerName ?? "-"}
          value={confirmation}
          onChange={setConfirmation}
          disabled={busy}
        />
      </ActionDialog>
    </ActionRow>
  );
}

function DeleteAccount({
  profileId,
  email,
  storeManaged,
  onDone,
}: {
  profileId: string;
  email: string;
  storeManaged: boolean;
  onDone: () => void;
}) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [busy, setBusy] = useState(false);
  const confirmed = confirmation.trim().toLowerCase() === email.trim().toLowerCase();
  const canSubmit = confirmed && reason.trim().length >= 3;

  async function run() {
    setBusy(true);
    const supabase = createClient();
    const { data, error } = await supabase.functions.invoke("admin-actions", {
      body: { action: "account.delete", profileId, reason },
    });
    setBusy(false);
    if (error || !data?.ok) {
      // The function refuses to delete an account whose web subscription it could not cancel, and
      // says so. "Check the logs" was the previous answer, which is advice rather than information
      // - and the last time deletion broke, the logs did not say why either. The refusal itself is
      // the useful thing, so it is what gets shown.
      toast.error(await functionErrorMessage(error, "Couldn't delete this account."));
      return;
    }
    toast.success("Account deleted.");
    setReason("");
    setConfirmation("");
    setOpen(false);
    onDone();
  }

  return (
    <ActionRow
      title="Delete this account"
      description={
        storeManaged
          ? "Permanent. Their app store subscription keeps charging until they cancel it."
          : "Permanent. Removes their login and ends any couple."
      }
    >
      <ActionDialog
        open={open}
        onOpenChange={(next) => {
          setOpen(next);
          if (!next) {
            setReason("");
            setConfirmation("");
          }
        }}
        busy={busy}
        trigger={<Button variant="destructive" size="sm" />}
        triggerLabel="Delete…"
        title="Delete this account?"
        description={
          <ul className="account-dialog-list">
            <li>
              Their name, photo and login are removed and sign-in is permanently disabled. The row
              stays: a hard delete would cascade and take their partner&apos;s side of a shared
              history with it.
            </li>
            <li>
              Any active couple is dissolved. The shared history is permanently deleted for both of
              them 90 days later, and nobody can bring that forward or extend it.
            </li>
            <li>A website subscription is cancelled first; if that fails, nothing is deleted.</li>
            {storeManaged && (
              <li className="is-alert">
                Their subscription was bought through an app store, so deleting will not cancel it.
                They must cancel it themselves, or they keep being charged for an account that no
                longer exists.
              </li>
            )}
          </ul>
        }
        canSubmit={canSubmit}
        onSubmit={run}
        actions={
          <Button type="submit" className={DANGER_SUBMIT} disabled={busy || !canSubmit}>
            {busy && <Loader2 className="h-4 w-4 animate-spin" />}
            Delete this account
          </Button>
        }
      >
        <ReasonField id="delete-reason" value={reason} onChange={setReason} disabled={busy} />
        <ConfirmField id="delete-confirm" expected={email} value={confirmation} onChange={setConfirmation} disabled={busy} />
      </ActionDialog>
    </ActionRow>
  );
}
