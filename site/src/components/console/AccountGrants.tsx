"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import { createClient } from "@/lib/supabase/client";
import { nullableArg } from "@/lib/db/nullableArg";

/**
 * The making-somebody-whole half of the console: the things support gives back when something went
 * wrong on our side, rather than the things it takes away.
 *
 * Kept visually apart from the destructive actions, and not inside a red-bordered card, because
 * they are not the same kind of act — granting a credit to somebody whose export failed twice
 * should not require reading past a delete button to reach.
 *
 * Same rule as everywhere else in here: a reason is required and the button stays disabled without
 * one. For the flight limit that matters twice over — it decides how much AeroAPI money an account
 * may spend, and `private.flight_limit_overrides`'s own comment is blunt about the consequence of
 * an unexplained row: "nobody will dare delete it."
 */
export function AccountGrants({
  profileId,
  override,
}: {
  profileId: string;
  override: { monthly_limit: number; note: string | null; created_at: string } | null;
}) {
  const router = useRouter();

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Grants</CardTitle>
        <CardDescription>
          Recorded against this account with the reason you give, the same as any other action.
        </CardDescription>
      </CardHeader>

      <CardContent className="space-y-6">
        <Grant
          profileId={profileId}
          rpc="admin_grant_streak_repair"
          title="Grant a streak repair"
          blurb="One repair, unconsumed. Use when a streak was lost to something that was our fault."
          onDone={() => router.refresh()}
        />

        <Separator />

        <Grant
          profileId={profileId}
          rpc="admin_grant_record_export"
          title="Grant a record export"
          blurb="One export. Premium already has unlimited exports, so this is for somebody on Plus."
          onDone={() => router.refresh()}
        />

        <Separator />

        <FlightLimit profileId={profileId} override={override} onDone={() => router.refresh()} />
      </CardContent>
    </Card>
  );
}

function Grant({
  profileId,
  rpc,
  title,
  blurb,
  onDone,
}: {
  profileId: string;
  rpc: "admin_grant_streak_repair" | "admin_grant_record_export";
  title: string;
  blurb: string;
  onDone: () => void;
}) {
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);

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
    onDone();
  }

  return (
    <div className="space-y-3">
      <div>
        <h3 className="text-sm font-medium">{title}</h3>
        <p className="mt-0.5 text-sm text-muted-foreground">{blurb}</p>
      </div>
      <Textarea
        rows={2}
        placeholder="Why, and who asked."
        value={reason}
        onChange={(e) => setReason(e.target.value)}
        disabled={busy}
        aria-label={`Reason for: ${title}`}
      />
      <Button variant="outline" disabled={busy || reason.trim().length < 3} onClick={run}>
        {busy && <Loader2 className="h-4 w-4 animate-spin" />}
        {title}
      </Button>
    </div>
  );
}

function FlightLimit({
  profileId,
  override,
  onDone,
}: {
  profileId: string;
  override: { monthly_limit: number; note: string | null; created_at: string } | null;
  onDone: () => void;
}) {
  const [limit, setLimit] = useState(override ? String(override.monthly_limit) : "");
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);

  const parsed = limit.trim() === "" ? null : Number(limit);
  const limitValid = parsed === null || (Number.isInteger(parsed) && parsed >= 0);

  async function run(removing: boolean) {
    setBusy(true);
    const supabase = createClient();
    const { error } = await supabase.rpc("admin_set_flight_limit", {
      p_profile_id: profileId,
      // Null REMOVES the override — see nullableArg, and admin_grants_test pins the behaviour.
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
    onDone();
  }

  return (
    <div className="space-y-3">
      <div>
        <h3 className="text-sm font-medium">Flight tracking limit</h3>
        <p className="mt-0.5 text-sm text-muted-foreground">
          Replaces the tier default for this couple — either partner holding an override raises the
          shared pool. This is what the account may spend at AeroAPI, so it is the one grant here
          with a bill attached. Zero freezes tracking outright; it is the same mechanism pointed the
          other way.
        </p>
        {override && (
          <p className="mt-1 text-sm">
            Currently <strong>{override.monthly_limit}</strong> a month
            {override.note ? ` — ${override.note}` : ""}
          </p>
        )}
      </div>

      <div className="space-y-1.5">
        <Label htmlFor="flight-limit">Monthly limit</Label>
        <Input
          id="flight-limit"
          inputMode="numeric"
          placeholder="Leave blank to use the tier default"
          value={limit}
          onChange={(e) => setLimit(e.target.value)}
          disabled={busy}
        />
        {!limitValid && <p className="text-sm text-destructive">Enter a whole number, zero or more.</p>}
      </div>

      <Textarea
        rows={2}
        placeholder="Why this account needs a different limit."
        value={reason}
        onChange={(e) => setReason(e.target.value)}
        disabled={busy}
        aria-label="Reason for the flight limit override"
      />

      <div className="flex flex-wrap gap-2">
        <Button
          variant="outline"
          disabled={busy || !limitValid || parsed === null || reason.trim().length < 3}
          onClick={() => run(false)}
        >
          {busy && <Loader2 className="h-4 w-4 animate-spin" />}
          {override ? "Update override" : "Set override"}
        </Button>
        {override && (
          <Button
            variant="ghost"
            disabled={busy || reason.trim().length < 3}
            onClick={() => run(true)}
          >
            Remove override
          </Button>
        )}
      </div>
    </div>
  );
}
