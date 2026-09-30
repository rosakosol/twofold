"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Loader2, TriangleAlert } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { createClient } from "@/lib/supabase/client";
import { APPLE_SUBSCRIPTIONS_URL } from "@/lib/account/subscription";

/**
 * Deletion, with the app's own warnings rather than new ones.
 *
 * Every sentence below is DeleteAccountView's, because somebody who read the warning in the app
 * and then does this on the web must not be told two different things about what happens to their
 * shared history. The facts are load-bearing: the 90-day clock cannot be brought forward or
 * extended by anyone, the partner's side of a shared history is not erased, and an export has to
 * happen before deletion because there is no signing back in afterwards.
 *
 * The confirmation is typing the account's own email. A second "are you sure" is a reflex people
 * clear without reading; typing the address is a deliberate act that cannot be done by accident,
 * and it is the same control the support console will use for the same operation.
 */
/** The archive's own purge date, spelled the way the rest of the account page spells dates.
 *  A bad value degrades to the undated wording rather than printing "Invalid Date" in a warning. */
function longDate(iso: string): string {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return "the date already set";
  return date.toLocaleDateString(undefined, { year: "numeric", month: "long", day: "numeric" });
}

export function DangerZone({
  email,
  hasPartner,
  partnerName,
  archivedCount,
  earliestArchivePurgeAt,
  storeManagedSubscription,
}: {
  email: string;
  hasPartner: boolean;
  partnerName: string | null;
  /** Dissolved couples this person is a member of — the archives deletion does NOT bring forward. */
  archivedCount: number;
  /** `couples.scheduled_purge_at` of the archive that goes first, or null if there are none. */
  earliestArchivePurgeAt: string | null;
  storeManagedSubscription: boolean;
}) {
  const router = useRouter();
  const [confirmation, setConfirmation] = useState("");
  const [isDeleting, setIsDeleting] = useState(false);
  const name = partnerName || "your partner";
  const canDelete = confirmation.trim().toLowerCase() === email.trim().toLowerCase();

  async function handleDelete() {
    setIsDeleting(true);
    const supabase = createClient();
    const { data, error } = await supabase.functions.invoke("delete-account", { body: {} });

    if (error || !data?.ok) {
      setIsDeleting(false);
      // delete-account refuses to delete when it cannot cancel a web subscription first, on the
      // grounds that a live subscription against an account nobody can sign in to is a charge the
      // person cannot stop. That refusal is a success of the design, so it is reported as a
      // "nothing happened, try again" rather than as a failure of their request.
      toast.error(
        "We couldn't delete your account just now, and nothing has been changed. Please try again, or email support@twofoldapp.com.au.",
      );
      return;
    }

    await supabase.auth.signOut();
    toast.success("Your account has been deleted.");
    router.push("/");
  }

  return (
    <Card className="border-destructive/40">
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <TriangleAlert className="h-4 w-4 text-destructive" />
          Delete your account
        </CardTitle>
        <CardDescription>This cannot be undone.</CardDescription>
      </CardHeader>

      <CardContent className="space-y-4">
        <ul className="space-y-2 text-sm text-muted-foreground">
          <li>
            Your name, photo, and login are permanently removed. You won&apos;t be able to sign back
            in.
          </li>
          {/* Three states, matching DeleteAccountView: a live partner, an old archive, or neither.
              The web had only the first two, so the archive sentence was shown to everybody without
              a live partner — including somebody who has never connected to anyone, who was told
              their history "stays with the person you shared it with" about a person who does not
              exist. The app has always hidden these rows from that person for exactly that reason.

              The archive case gets its purge date rather than "90 days". Its clock started when the
              connection dissolved, not today, so counting 90 from here would be wrong — and
              `scheduled_purge_at` is the same date the app's Archived Data screen shows, which is
              the point of reading it rather than computing one. */}
          {hasPartner ? (
            <>
              <li>
                Trips, memories, and photos you shared with {name} stay with them — deleting your
                account doesn&apos;t erase their side of a shared history.
              </li>
              <li>
                Deleting your account ends your connection, and your shared history is permanently
                deleted for both of you 90 days after that. Nobody can bring that forward, and
                nobody can extend it.
              </li>
            </>
          ) : archivedCount > 0 ? (
            <li>
              {archivedCount === 1
                ? "Your archived history stays with the person you shared it with"
                : "Your archived histories stay with the people you shared them with"}
              , and {archivedCount === 1 ? "is" : "are"} permanently deleted
              {earliestArchivePurgeAt
                ? ` on the date already set for ${archivedCount === 1 ? "it" : "the first of them"}, ${longDate(earliestArchivePurgeAt)}`
                : " on the date already set"}
              . Deleting your account doesn&apos;t erase their side of it, and doesn&apos;t change
              that date.
            </li>
          ) : null}
          <li>
            If you want to keep a copy, export it from the app before you delete your account — you
            won&apos;t be able to sign in to get it afterwards.
          </li>
          {storeManagedSubscription && (
            // The one thing deletion genuinely cannot do for them. delete-account cancels a website
            // subscription before it deletes anything, and refuses to proceed if it can't — but an
            // App Store subscription is Apple's, and saying nothing here would leave somebody
            // paying for an account that no longer exists.
            <li className="text-destructive">
              Your subscription was bought through an app store, so deleting your account does not
              cancel it. Cancel it yourself first —{" "}
              <a
                href={APPLE_SUBSCRIPTIONS_URL}
                target="_blank"
                rel="noopener noreferrer"
                className="underline"
              >
                manage subscriptions
              </a>
              .
            </li>
          )}
        </ul>

        <div className="space-y-1.5 pt-2">
          <Label htmlFor="confirm-email">
            Type <span className="font-mono">{email}</span> to confirm
          </Label>
          <Input
            id="confirm-email"
            autoComplete="off"
            value={confirmation}
            onChange={(e) => setConfirmation(e.target.value)}
            disabled={isDeleting}
          />
        </div>

        <Button variant="destructive" disabled={!canDelete || isDeleting} onClick={handleDelete}>
          {isDeleting && <Loader2 className="h-4 w-4 animate-spin" />}
          Delete my account
        </Button>
      </CardContent>
    </Card>
  );
}
