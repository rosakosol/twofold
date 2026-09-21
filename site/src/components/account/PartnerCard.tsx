"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import { createClient } from "@/lib/supabase/client";

/**
 * Disconnecting is destructive to two people, only one of whom is present — so the copy here is
 * taken from the app's own DisconnectPartnerView rather than written fresh. Someone who reads the
 * warning in the app and then does it on the web must not be told two different things about what
 * is about to happen to their shared history.
 *
 * The one thing deliberately NOT offered here is blocking. The app pairs disconnect with "block
 * and report", because that flow exists for someone getting away from an abusive partner and needs
 * the reporting path beside it. Putting a bare disconnect on the web is fine; putting a block
 * button here without the reporting flow, the 48-hour response promise and the "we never tell them
 * you got in touch" assurance would be a worse version of something that matters.
 */
export function PartnerCard({
  partnerName,
  togetherSince,
  coupleId,
}: {
  partnerName: string | null;
  togetherSince: string | null;
  coupleId: string | null;
}) {
  const router = useRouter();
  const [isLeaving, setIsLeaving] = useState(false);
  const name = partnerName || "your partner";

  async function handleDisconnect() {
    if (!coupleId) return;
    setIsLeaving(true);

    // The same security-definer RPC the app calls. It keys off auth.uid(), so it can only ever
    // dissolve a couple the caller is actually in — there is no "disconnect someone else" shape to
    // get wrong here.
    const supabase = createClient();
    const { error } = await supabase.rpc("leave_couple", { p_couple_id: coupleId });
    setIsLeaving(false);

    if (error) {
      toast.error("We couldn't disconnect you just now. Please try again.");
      return;
    }
    toast.success(`You're no longer connected to ${name}.`);
    router.refresh();
  }

  if (!coupleId) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Partner</CardTitle>
          <CardDescription>You&apos;re not currently connected to a partner.</CardDescription>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground">
            Connecting happens in the app — open Twofold and share your invite code.
          </p>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Partner</CardTitle>
        <CardDescription>
          Connected to {name}
          {togetherSince ? ` · together since ${formatDate(togetherSince)}` : ""}
        </CardDescription>
      </CardHeader>

      <CardContent className="space-y-4">
        <p className="text-sm text-muted-foreground">
          Disconnecting archives everything you&apos;ve shared, and lets you connect with someone
          new. Your shared history is archived, not deleted — it goes on the usual 90-day timer.
        </p>

        <AlertDialog>
          <AlertDialogTrigger
            render={
              <Button variant="outline" disabled={isLeaving}>
                {isLeaving && <Loader2 className="h-4 w-4 animate-spin" />}
                Disconnect {name}
              </Button>
            }
          />
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>Disconnect {name}?</AlertDialogTitle>
              <AlertDialogDescription>
                You&apos;ll be disconnected and your shared history is archived, not deleted — it
                goes on the usual 90-day timer, and reconnecting before it expires would offer it
                back to you. If {name} is the one paying for your subscription, you&apos;ll drop
                back to the free plan, since you won&apos;t be covered by their purchase any more.
              </AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
              <AlertDialogCancel>Stay connected</AlertDialogCancel>
              <AlertDialogAction onClick={handleDisconnect}>Disconnect</AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>

        <p className="text-xs text-muted-foreground">
          If {name} has shared something abusive, or is using Twofold to harm you, the app&apos;s
          Disconnect screen can block and report them as well. We aim to respond within 48 hours,
          and we never tell them you got in touch.
        </p>
      </CardContent>
    </Card>
  );
}

function formatDate(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleDateString(undefined, { year: "numeric", month: "long", day: "numeric" });
}
