"use client";

import { useState } from "react";
import Link from "next/link";
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

export type CoupleArchive = {
  couple_id: string;
  partner_id: string;
  dissolved_at: string | null;
  scheduled_purge_at: string | null;
  self_deleted: boolean;
  partner_deleted: boolean;
};

/**
 * An account's archived relationships, and the one exception to the 90-day timer.
 *
 * `AccountActions` only offers what the owner could do themselves. This purge breaks that rule
 * because nobody is left to do it: it is offered only when both partners have deleted their
 * accounts, so no living account loses its copy. `admin_purge_couple_archive` enforces the same
 * condition itself. Hiding the button here is for clarity, not what keeps this safe.
 */
export function AccountArchives({ archives }: { archives: CoupleArchive[] }) {
  const router = useRouter();
  if (archives.length === 0) return null;

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Archived relationships</CardTitle>
        <CardDescription>
          Shared history from a couple that ended. Deleted automatically when its 90 days are up.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-6">
        {archives.map((archive, i) => (
          <div key={archive.couple_id} className="space-y-6">
            {i > 0 && <Separator />}
            <Archive archive={archive} onDone={() => router.refresh()} />
          </div>
        ))}
      </CardContent>
    </Card>
  );
}

function Archive({ archive, onDone }: { archive: CoupleArchive; onDone: () => void }) {
  const [reason, setReason] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [busy, setBusy] = useState(false);
  const bothDeleted = archive.self_deleted && archive.partner_deleted;
  // Partners' names are scrubbed to "Deleted User" by the time this is offered, so the id is the
  // only specific thing left to type.
  const expected = archive.couple_id.slice(0, 8);
  const confirmed = confirmation.trim().toLowerCase() === expected;

  async function run() {
    setBusy(true);
    const supabase = createClient();
    const { error } = await supabase.rpc("admin_purge_couple_archive", {
      p_couple_id: archive.couple_id,
      p_reason: reason,
    });
    setBusy(false);
    if (error) {
      toast.error(error.message);
      return;
    }
    toast.success("Purged. The shared history is permanently deleted.");
    setReason("");
    setConfirmation("");
    onDone();
  }

  return (
    <div className="space-y-3">
      <div className="space-y-1.5 text-sm">
        <Row label="Couple" value={<span className="font-mono">{expected}</span>} />
        <Row label="Ended" value={formatDate(archive.dissolved_at)} />
        <Row label="Deletes automatically" value={formatDate(archive.scheduled_purge_at)} />
        <Row label="This account" value={archive.self_deleted ? "deleted" : "active"} />
        <Row
          label="Partner"
          value={
            <Link href={`/admin/users/${archive.partner_id}`} className="underline underline-offset-4">
              {archive.partner_deleted ? "deleted" : "active"}
            </Link>
          }
        />
      </div>

      {!bothDeleted ? (
        <p className="text-sm text-muted-foreground">
          Can&apos;t be purged early. Someone still has an account that can read this history, so
          it waits for its timer. One partner can never delete the other&apos;s copy.
        </p>
      ) : (
        <>
          <p className="text-sm text-muted-foreground">
            Both partners have deleted their accounts, so nobody can read or restore this. Purging
            permanently deletes the memories, photos, trips, flights and game answers now instead
            of on the date above. This cannot be undone.
          </p>
          <div className="space-y-1.5">
            <Label htmlFor={`purge-reason-${archive.couple_id}`}>Reason</Label>
            <Textarea
              id={`purge-reason-${archive.couple_id}`}
              rows={2}
              placeholder="Why this is being done, and who asked."
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              disabled={busy}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor={`purge-confirm-${archive.couple_id}`}>
              Type <span className="font-mono">{expected}</span> to confirm
            </Label>
            <Input
              id={`purge-confirm-${archive.couple_id}`}
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
            Purge now
          </Button>
        </>
      )}
    </div>
  );
}

function Row({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex items-baseline justify-between gap-4">
      <span className="shrink-0 text-muted-foreground">{label}</span>
      <span className="truncate text-right">{value}</span>
    </div>
  );
}

function formatDate(value: string | null): string {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return date.toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" });
}
