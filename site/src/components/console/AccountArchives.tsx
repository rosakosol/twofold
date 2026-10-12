"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Archive as ArchiveIcon, Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { createClient } from "@/lib/supabase/client";
import { shortDate } from "@/lib/console/format";
import { AccountCard, AccountSection, ActionRow, Fact, Facts } from "@/components/console/AccountLayout";
import { ActionDialog, ConfirmField, DANGER_SUBMIT, ReasonField } from "@/components/console/AccountDialog";
import { InfoTip } from "@/components/console/InfoTip";

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
    <AccountSection
      id="archives"
      title="Archived relationships"
      icon={<ArchiveIcon aria-hidden className="text-muted-foreground" />}
      description="Deleted automatically when their 90 days are up."
    >
      {archives.map((archive) => (
        <Archive key={archive.couple_id} archive={archive} onDone={() => router.refresh()} />
      ))}
    </AccountSection>
  );
}

function Archive({ archive, onDone }: { archive: CoupleArchive; onDone: () => void }) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [busy, setBusy] = useState(false);
  const bothDeleted = archive.self_deleted && archive.partner_deleted;
  // Partners' names are scrubbed to "Deleted User" by the time this is offered, so the id is the
  // only specific thing left to type.
  const expected = archive.couple_id.slice(0, 8);
  const confirmed = confirmation.trim().toLowerCase() === expected;
  const canSubmit = confirmed && reason.trim().length >= 3;

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
    setOpen(false);
    onDone();
  }

  return (
    <AccountCard title={<>Couple <span className="console-mono">{expected}</span></>}>
      <Facts>
        <Fact label="Ended" value={shortDate(archive.dissolved_at)} />
        <Fact label="Deletes automatically" value={shortDate(archive.scheduled_purge_at)} />
        <Fact label="This account" value={archive.self_deleted ? "Deleted" : "Active"} />
        <Fact
          label="Partner"
          value={
            <Link href={`/admin/users/${archive.partner_id}`} className="underline underline-offset-4">
              {archive.partner_deleted ? "Deleted" : "Active"}
            </Link>
          }
        />
      </Facts>

      <ul className="account-actions mt-2 border-t border-border pt-3">
        {!bothDeleted ? (
          <ActionRow
            title="Purge early"
            info={
              <InfoTip label="Why this archive can't be purged early">
                <p>
                  Someone still has an account that can read this history, so it waits for its timer.
                  One partner can never delete the other&apos;s copy.
                </p>
              </InfoTip>
            }
            description="Not available while either partner still has an account."
          />
        ) : (
          <ActionRow title="Purge early" description="Both partners are deleted. Deletes it now, for good.">
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
              triggerLabel="Purge…"
              title="Purge this archive now?"
              description={
                <p>
                  Both partners have deleted their accounts, so nobody can read or restore this.
                  Purging permanently deletes the memories, photos, trips, flights and game answers
                  now instead of on {shortDate(archive.scheduled_purge_at)}. This cannot be undone.
                </p>
              }
              canSubmit={canSubmit}
              onSubmit={run}
              actions={
                <Button type="submit" className={DANGER_SUBMIT} disabled={busy || !canSubmit}>
                  {busy && <Loader2 className="h-4 w-4 animate-spin" />}
                  Purge now
                </Button>
              }
            >
              <ReasonField
                id={`purge-reason-${archive.couple_id}`}
                value={reason}
                onChange={setReason}
                disabled={busy}
              />
              <ConfirmField
                id={`purge-confirm-${archive.couple_id}`}
                expected={expected}
                value={confirmation}
                onChange={setConfirmation}
                disabled={busy}
              />
            </ActionDialog>
          </ActionRow>
        )}
      </ul>
    </AccountCard>
  );
}
