"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Loader2, TriangleAlert } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import { createClient } from "@/lib/supabase/client";
import { functionErrorMessage } from "@/lib/supabase/functionError";
import { cancellability } from "@/lib/console/accountDetail";

/**
 * The console's write surface for one account.
 *
 * Everything here is something the account's owner could do themselves if they could sign in — and
 * that is the boundary. This console exists because they sometimes cannot: the app is refusing,
 * they have lost access to the address, or email is the only channel they have. It does not exist
 * to do things to people, so nothing here has a counterpart the owner lacks.
 *
 * Three rules, applied to every action:
 *
 *   1. A reason is required, and the button stays disabled without one. Not because anybody reads
 *      them routinely, but because an unexplained destructive action found in the log in two years
 *      is indistinguishable from a mistake.
 *   2. The confirmation is typing something specific — the partner's name, the account's email —
 *      rather than pressing "are you sure". A second button is a reflex people clear without
 *      reading; typing cannot be done by accident.
 *   3. Nothing is offered that cannot actually be done. An App Store subscription shows why it is
 *      not cancellable here instead of a button that would report success for a charge that is
 *      still coming.
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

  if (alreadyDeleted) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Actions</CardTitle>
          <CardDescription>
            This account is already deleted. Sign-in is permanently disabled and cannot be restored.
          </CardDescription>
        </CardHeader>
      </Card>
    );
  }

  return (
    <Card className="border-destructive/40">
      <CardHeader>
        <CardTitle className="flex items-center gap-2 text-base">
          <TriangleAlert className="h-4 w-4 text-destructive" />
          Actions
        </CardTitle>
        <CardDescription>
          Every one of these is recorded against this account with the reason you give.
        </CardDescription>
      </CardHeader>

      <CardContent className="space-y-6">
        {subscriptionActive && (
          <>
            <CancelSubscription
              profileId={profileId}
              ours={subscription.ours}
              label={subscription.label}
              onDone={() => router.refresh()}
            />
            <Separator />
          </>
        )}

        {couple && (
          <>
            <Disconnect
              profileId={profileId}
              coupleId={couple.id}
              partnerName={couple.partnerFirstName}
              onDone={() => router.refresh()}
            />
            <Separator />
          </>
        )}

        <DeleteAccount
          profileId={profileId}
          email={email}
          storeManaged={subscriptionActive && !subscription.ours}
          onDone={() => router.refresh()}
        />
      </CardContent>
    </Card>
  );
}

function ReasonField({
  id,
  value,
  onChange,
  disabled,
}: {
  id: string;
  value: string;
  onChange: (v: string) => void;
  disabled: boolean;
}) {
  return (
    <div className="space-y-1.5">
      <Label htmlFor={id}>Reason</Label>
      <Textarea
        id={id}
        rows={2}
        placeholder="Why this is being done, and who asked."
        value={value}
        onChange={(e) => onChange(e.target.value)}
        disabled={disabled}
      />
    </div>
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
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);

  async function run() {
    setBusy(true);
    const supabase = createClient();
    const { data, error } = await supabase.functions.invoke("admin-actions", {
      body: { action: "subscription.cancel", profileId, reason },
    });
    setBusy(false);
    if (error || !data?.ok) {
      // The function's own refusal — "no web subscription", "not authorised", a RevenueCat error —
      // rather than one sentence covering all of them. It arrives on the error rather than in
      // `data`, which is null for every non-2xx; see functionErrorMessage.
      toast.error(await functionErrorMessage(error, "Couldn't cancel that subscription."));
      return;
    }
    // Zero is the App Store case reaching here anyway — reported plainly rather than as success,
    // so nobody tells a customer a charge has stopped when it has not.
    if (data.cancelled === 0) {
      toast.warning("Nothing was cancelled — no web subscription found on this account.");
    } else {
      toast.success("Cancelled. It won't renew; they keep it until the period they've paid for ends.");
    }
    setReason("");
    onDone();
  }

  return (
    <div className="space-y-3">
      <div>
        <h3 className="text-sm font-medium">Cancel subscription</h3>
        <p className="mt-0.5 text-sm text-muted-foreground">{label}</p>
      </div>

      {!ours ? (
        <p className="text-sm text-muted-foreground">
          Not cancellable from here. Tell them to cancel it where they bought it — for an App Store
          subscription that is Settings → Apple Account → Subscriptions on their device, and Apple
          gives us no way to do it for them.
        </p>
      ) : (
        <>
          <p className="text-sm text-muted-foreground">
            Stops the renewal. They keep the plan until the end of the period already paid for —
            Stripe refunds nothing, so ending it now would take time they bought.
          </p>
          <ReasonField id="cancel-reason" value={reason} onChange={setReason} disabled={busy} />
          <Button variant="outline" disabled={busy || reason.trim().length < 3} onClick={run}>
            {busy && <Loader2 className="h-4 w-4 animate-spin" />}
            Cancel their subscription
          </Button>
        </>
      )}
    </div>
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
  const [reason, setReason] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [busy, setBusy] = useState(false);
  const name = partnerName || "their partner";
  const expected = (partnerName || "").trim().toLowerCase();
  const confirmed = expected !== "" && confirmation.trim().toLowerCase() === expected;

  async function run() {
    setBusy(true);
    const supabase = createClient();
    // `p_on_behalf_of` is this account, not the admin. The couple row must record that THIS person
    // left — that is what the app reads, and it decides which partner gets the "your subscription
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
    onDone();
  }

  return (
    <div className="space-y-3">
      <div>
        <h3 className="text-sm font-medium">Disconnect from {name}</h3>
        <p className="mt-0.5 text-sm text-muted-foreground">
          Performed as this account, so the record shows they left — which is what decides who gets
          the subscription-lapse notice. Shared history is archived, not deleted, on the usual
          90-day timer, and reconnecting before it expires would offer it back.
        </p>
      </div>

      <ReasonField id="disconnect-reason" value={reason} onChange={setReason} disabled={busy} />

      <div className="space-y-1.5">
        <Label htmlFor="disconnect-confirm">
          Type <span className="font-mono">{partnerName ?? "—"}</span> to confirm
        </Label>
        <Input
          id="disconnect-confirm"
          autoComplete="off"
          value={confirmation}
          onChange={(e) => setConfirmation(e.target.value)}
          disabled={busy}
        />
      </div>

      <Button
        variant="outline"
        disabled={busy || !confirmed || reason.trim().length < 3}
        onClick={run}
      >
        {busy && <Loader2 className="h-4 w-4 animate-spin" />}
        Disconnect them
      </Button>
    </div>
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
  const [reason, setReason] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [busy, setBusy] = useState(false);
  const confirmed = confirmation.trim().toLowerCase() === email.trim().toLowerCase();

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
      // — and the last time deletion broke, the logs did not say why either. The refusal itself is
      // the useful thing, so it is what gets shown.
      toast.error(await functionErrorMessage(error, "Couldn't delete this account."));
      return;
    }
    toast.success("Account deleted.");
    setReason("");
    setConfirmation("");
    onDone();
  }

  return (
    <div className="space-y-3">
      <div>
        <h3 className="text-sm font-medium text-destructive">Delete this account</h3>
        <ul className="mt-1 space-y-1 text-sm text-muted-foreground">
          <li>
            Their name, photo and login are removed, and sign-in is permanently disabled. The row
            itself survives — a hard delete would cascade and take their partner&apos;s side of a
            shared history with it.
          </li>
          <li>
            Any active couple is dissolved. The shared history is permanently deleted for both of
            them 90 days later, and nobody can bring that forward or extend it.
          </li>
          <li>
            A website subscription is cancelled first; if that fails, nothing is deleted at all.
          </li>
          {storeManaged && (
            <li className="text-destructive">
              This account&apos;s subscription was bought through an app store, so deleting will not
              cancel it. They must cancel it themselves, or they keep being charged for an account
              that no longer exists.
            </li>
          )}
        </ul>
      </div>

      <ReasonField id="delete-reason" value={reason} onChange={setReason} disabled={busy} />

      <div className="space-y-1.5">
        <Label htmlFor="delete-confirm">
          Type <span className="font-mono">{email}</span> to confirm
        </Label>
        <Input
          id="delete-confirm"
          autoComplete="off"
          value={confirmation}
          onChange={(e) => setConfirmation(e.target.value)}
          disabled={busy}
        />
      </div>

      <Button
        variant="destructive"
        disabled={busy || !confirmed || reason.trim().length < 3}
        onClick={run}
      >
        {busy && <Loader2 className="h-4 w-4 animate-spin" />}
        Delete this account
      </Button>
    </div>
  );
}
