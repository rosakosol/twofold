"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Gift, Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { createClient } from "@/lib/supabase/client";
import { nullableArg } from "@/lib/db/nullableArg";
import { AccountSection, ActionRow } from "@/components/console/AccountLayout";
import { ActionDialog, ReasonField } from "@/components/console/AccountDialog";
import { InfoTip } from "@/components/console/InfoTip";

export type FlightOverride = { monthly_limit: number; note: string | null; created_at: string };

/**
 * The making-somebody-whole half of the console: the things support gives back when something went
 * wrong on our side, rather than the things it takes away.
 *
 * Kept apart from the danger zone, and not red, because they are not the same kind of act -
 * granting a credit to somebody whose export failed twice should not require reading past a delete
 * button to reach.
 *
 * Each grant is a row with its current value and a button; the reason is asked for in the dialog
 * the button opens. Same rule as everywhere else in here: a reason is required and the submit stays
 * disabled without one. For the flight limit that matters twice over - it decides how much AeroAPI
 * money an account may spend, and `private.flight_limit_overrides`'s own comment is blunt about the
 * consequence of an unexplained row: "nobody will dare delete it."
 */
export function AccountGrants({
  profileId,
  override,
  credits,
  tierLimit,
}: {
  profileId: string;
  override: FlightOverride | null;
  credits: { streak_repair_unused: number; record_export_unused: number };
  /** The couple's current monthly flight allowance (`flight_limit_for_couple`: either partner's
   *  override, else the tier's), shown beside "Tier default". Null when there is no couple. */
  tierLimit: number | null;
}) {
  const router = useRouter();

  return (
    <AccountSection
      id="grants"
      title="Grants"
      icon={<Gift aria-hidden className="text-[color:var(--success)]" />}
      description="Recorded with the reason you give."
    >
      <div className="account-card">
        <ul className="account-actions">
          <Grant
            profileId={profileId}
            rpc="admin_grant_streak_repair"
            title="Streak repair"
            dialogTitle="Grant a streak repair"
            description="For a streak lost to something on our side."
            detail="Adds one unused streak repair to this account. Use it when a streak was lost to something that was our fault."
            unused={credits.streak_repair_unused}
            onDone={() => router.refresh()}
          />
          <Grant
            profileId={profileId}
            rpc="admin_grant_record_export"
            title="Record export"
            dialogTitle="Grant a record export"
            description="One extra export, for someone on Plus."
            detail="Adds one Relationship Record export. Premium already has unlimited exports, so this is for somebody on Plus."
            unused={credits.record_export_unused}
            onDone={() => router.refresh()}
          />
          <FlightLimit
            profileId={profileId}
            override={override}
            tierLimit={tierLimit}
            onDone={() => router.refresh()}
          />
        </ul>
      </div>
    </AccountSection>
  );
}

function Grant({
  profileId,
  rpc,
  title,
  dialogTitle,
  description,
  detail,
  unused,
  onDone,
}: {
  profileId: string;
  rpc: "admin_grant_streak_repair" | "admin_grant_record_export";
  title: string;
  dialogTitle: string;
  description: string;
  detail: string;
  unused: number;
  onDone: () => void;
}) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const canSubmit = reason.trim().length >= 3;

  async function run() {
    setBusy(true);
    const supabase = createClient();
    const { error } = await supabase.rpc(rpc, { p_profile_id: profileId, p_reason: reason });
    setBusy(false);
    if (error) {
      toast.error(error.message);
      return;
    }
    toast.success("Granted.");
    setReason("");
    setOpen(false);
    onDone();
  }

  return (
    <ActionRow title={title} description={description} value={`${unused} unused`}>
      <ActionDialog
        open={open}
        onOpenChange={(next) => {
          setOpen(next);
          if (!next) setReason("");
        }}
        busy={busy}
        trigger={<Button variant="outline" size="sm" />}
        triggerLabel="Grant"
        title={dialogTitle}
        description={<p>{detail}</p>}
        canSubmit={canSubmit}
        onSubmit={run}
        actions={
          <Button type="submit" disabled={busy || !canSubmit}>
            {busy && <Loader2 className="h-4 w-4 animate-spin" />}
            {dialogTitle}
          </Button>
        }
      >
        <ReasonField
          id={`${rpc}-reason`}
          value={reason}
          onChange={setReason}
          disabled={busy}
          placeholder="Why, and who asked."
        />
      </ActionDialog>
    </ActionRow>
  );
}

function FlightLimit({
  profileId,
  override,
  tierLimit,
  onDone,
}: {
  profileId: string;
  override: FlightOverride | null;
  tierLimit: number | null;
  onDone: () => void;
}) {
  const [open, setOpen] = useState(false);
  const [limit, setLimit] = useState(override ? String(override.monthly_limit) : "");
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);

  const parsed = limit.trim() === "" ? null : Number(limit);
  const limitValid = parsed === null || (Number.isInteger(parsed) && parsed >= 0);
  const reasonGiven = reason.trim().length >= 3;
  const canSet = limitValid && parsed !== null && reasonGiven;

  async function run(removing: boolean) {
    setBusy(true);
    const supabase = createClient();
    const { error } = await supabase.rpc("admin_set_flight_limit", {
      p_profile_id: profileId,
      // Null REMOVES the override - see nullableArg, and admin_grants_test pins the behaviour.
      p_monthly_limit: nullableArg(removing ? null : parsed),
      p_reason: reason,
    });
    setBusy(false);
    if (error) {
      toast.error(error.message);
      return;
    }
    toast.success(removing ? "Override removed." : "Override set.");
    setReason("");
    if (removing) setLimit("");
    setOpen(false);
    onDone();
  }

  return (
    <ActionRow
      title="Flight tracking limit"
      info={
        <InfoTip label="How the flight tracking limit works">
          <p>
            An override replaces the tier default for this couple. Either partner holding one raises
            the shared pool.
          </p>
          <p>
            This is what the account may spend at AeroAPI, so it is the one grant with a bill
            attached. Zero freezes tracking outright.
          </p>
        </InfoTip>
      }
      description="Flights this couple can track each month."
      value={
        override ? (
          <>
            Override: {override.monthly_limit}/month
            {override.note && <span className="muted">{override.note}</span>}
          </>
        ) : (
          <>
            Tier default
            {/* The couple's allowance, not the tier's: a partner's override raises it too. */}
            {tierLimit !== null && <span className="muted">{tierLimit}/month for the couple</span>}
          </>
        )
      }
    >
      <ActionDialog
        open={open}
        onOpenChange={(next) => {
          setOpen(next);
          // Start from what is stored each time, not from an abandoned edit.
          if (next) setLimit(override ? String(override.monthly_limit) : "");
          if (!next) setReason("");
        }}
        busy={busy}
        trigger={<Button variant="outline" size="sm" />}
        triggerLabel="Change"
        title="Flight tracking limit"
        description={
          <>
            <p>
              Replaces the tier default for this couple; either partner holding an override raises
              the shared pool. This is what the account may spend at AeroAPI, so it has a bill
              attached. Zero freezes tracking.
            </p>
            {override && (
              <p className="text-foreground">
                Currently <strong>{override.monthly_limit}</strong> a month
                {override.note ? ` - ${override.note}` : ""}
              </p>
            )}
          </>
        }
        canSubmit={canSet}
        onSubmit={() => run(false)}
        actions={
          <>
            {override && (
              <Button type="button" variant="outline" disabled={busy || !reasonGiven} onClick={() => run(true)}>
                Remove override
              </Button>
            )}
            <Button type="submit" disabled={busy || !canSet}>
              {busy && <Loader2 className="h-4 w-4 animate-spin" />}
              {override ? "Update override" : "Set override"}
            </Button>
          </>
        }
      >
        <div className="space-y-1.5">
          <Label htmlFor="flight-limit">Monthly limit</Label>
          <Input
            id="flight-limit"
            inputMode="numeric"
            placeholder="Leave blank to use the tier default"
            value={limit}
            onChange={(e) => setLimit(e.target.value)}
            disabled={busy}
            aria-invalid={!limitValid || undefined}
            aria-describedby={!limitValid ? "flight-limit-error" : undefined}
          />
          {!limitValid && (
            <p id="flight-limit-error" className="text-sm text-destructive">
              Enter a whole number, zero or more.
            </p>
          )}
        </div>
        <ReasonField
          id="flight-limit-reason"
          value={reason}
          onChange={setReason}
          disabled={busy}
          placeholder="Why this account needs a different limit."
        />
      </ActionDialog>
    </ActionRow>
  );
}
