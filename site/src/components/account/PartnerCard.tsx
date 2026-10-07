"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Heart, Loader2 } from "lucide-react";
import { APP_STORE_URL } from "@/lib/marketing/config";
import { longDate } from "@/lib/account/subscription";
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
/** Two avatars and a heart, or your own beside a dashed empty circle when nobody is connected. */
function Pair({ me, partner }: { me: string; partner: string | null }) {
  return (
    <div className="account-pair" aria-hidden>
      <span className="pv-avatar pv-avatar-sam">{me.charAt(0).toUpperCase() || "Y"}</span>
      <span className="account-pair-heart">
        <Heart />
      </span>
      {partner ? (
        <span className="pv-avatar pv-avatar-alex">{partner.charAt(0).toUpperCase()}</span>
      ) : (
        <span className="account-pair-empty" />
      )}
    </div>
  );
}

export function PartnerCard({
  myName,
  partnerName,
  togetherSince,
  coupleId,
}: {
  myName: string;
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
      <section className="account-card is-centred" aria-labelledby="partner-title">
        <h2 id="partner-title" className="sr-only">
          Partner
        </h2>
        <Pair me={myName} partner={null} />
        <p className="account-plan">You&apos;re not connected to a partner yet</p>
        <p className="account-muted">Connecting happens in the app: open Twofold and share your invite code.</p>
        <div className="account-actions">
          <a className="btn btn-primary" href={APP_STORE_URL} data-appstore-link>
            Open Twofold
          </a>
        </div>
      </section>
    );
  }

  return (
    <section className="account-card" aria-labelledby="partner-title">
      <div className="account-card-head">
        <h2 id="partner-title">Partner</h2>
      </div>
      <div className="account-partner">
        <Pair me={myName} partner={name} />
        <div>
          <p className="account-plan">Connected to {name}</p>
          {togetherSince && longDate(togetherSince) && (
            <p className="account-muted">Together since {longDate(togetherSince)}</p>
          )}
        </div>
      </div>

      <p className="account-muted">
        Disconnecting archives everything you&apos;ve shared, and lets you connect with someone new. Your shared history
        is archived, not deleted. It goes on the usual 90-day timer.
      </p>

      <div className="account-actions">
        <AlertDialog>
          <AlertDialogTrigger
            render={
              <button type="button" className="btn btn-secondary" disabled={isLeaving}>
                {isLeaving && <Loader2 className="h-4 w-4 animate-spin" aria-hidden />}
                Disconnect {name}
              </button>
            }
          />
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>Disconnect {name}?</AlertDialogTitle>
              <AlertDialogDescription>
                You&apos;ll be disconnected and your shared history is archived, not deleted — it goes on the usual
                90-day timer, and reconnecting before it expires would offer it back to you. If {name} is the one paying
                for your subscription, yours ends with the connection, since you won&apos;t be covered by their purchase
                any more.
              </AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
              <AlertDialogCancel>Stay connected</AlertDialogCancel>
              <AlertDialogAction onClick={handleDisconnect}>Disconnect</AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
      </div>

      <p className="account-fine">
        If {name} has shared something abusive, or is using Twofold to harm you, the app&apos;s Disconnect screen can
        block and report them as well. We aim to respond within 48 hours, and we never tell them you got in touch.
      </p>
    </section>
  );
}
