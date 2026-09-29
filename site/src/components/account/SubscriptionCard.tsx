"use client";

import { useState } from "react";
import { toast } from "sonner";
import { ExternalLink, Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
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
import {
  APPLE_SUBSCRIPTIONS_URL,
  subscriptionControl,
  tierLabel,
  type SubscriptionSnapshot,
} from "@/lib/account/subscription";

/**
 * What this offers depends entirely on where the subscription was bought, which is why
 * `subscription_store` exists. An App Store subscription is Apple's and there is no API that ends
 * one; showing a cancel button for it would either do nothing or claim to have stopped a charge
 * that is still coming. So that case gets Apple's own settings link and an honest sentence.
 */
export function SubscriptionCard({ snapshot }: { snapshot: SubscriptionSnapshot }) {
  const control = subscriptionControl(snapshot);
  const [isCancelling, setIsCancelling] = useState(false);
  // Set once the request succeeds. The row is NOT updated here — RevenueCat is the source of truth
  // and its webhook is the only writer — so the card reports what was asked for rather than
  // pretending to know the new state.
  const [requested, setRequested] = useState(false);

  async function handleCancel() {
    setIsCancelling(true);
    const supabase = createClient();
    const { data, error } = await supabase.functions.invoke("cancel-my-subscription", { body: {} });
    setIsCancelling(false);

    if (error || !data?.ok) {
      toast.error(
        "We couldn't cancel your subscription just now, so nothing has changed — you're still subscribed. Please try again, or email support@twofoldapp.com.au.",
      );
      return;
    }
    setRequested(true);
    toast.success("Your subscription won't renew.");
  }

  return (
    <Card>
      <CardHeader>
        <div className="flex items-start justify-between gap-3">
          <div>
            <CardTitle>Subscription</CardTitle>
            <CardDescription>{planSummary(snapshot)}</CardDescription>
          </div>
          <div className="flex shrink-0 gap-2">
            {/* Only on a positive `true`. Null means the webhook has not spoken for this
                subscription yet, and a "Free trial" badge on somebody who is actually paying is a
                worse error than no badge at all. */}
            {snapshot.active && snapshot.isTrial === true && <Badge>Free trial</Badge>}
            {snapshot.active && <Badge variant="secondary">{tierLabel(snapshot.tier)}</Badge>}
          </div>
        </div>
      </CardHeader>

      <CardContent className="space-y-4">
        {control.kind === "none" && (
          <p className="text-sm text-muted-foreground">
            You&apos;re on the free plan. <a href="/pricing" className="underline">See what&apos;s in Plus and Premium</a>.
          </p>
        )}

        {control.kind === "web" && !requested && snapshot.willRenew !== false && (
          <>
            {/* Three readings, not two. `isTrial` is null when the webhook has not yet seen this
                subscription, and null is not false.

                The trial sentence says what is certainly true — no charge — rather than when access
                stops, which is not established. RevenueCat documents a paid period as running to its
                end and says nothing about trials. An earlier version of this claimed access ended
                immediately, on the strength of a sandbox subscription that looked like it: sandbox
                compresses a fourteen-day trial to about four minutes and a month to five, so a
                cancellation forty minutes in had in fact converted and renewed a dozen times, and was
                ending at an ordinary period boundary. Worth knowing before trusting any duration
                measured against test data. */}
            <p className="text-sm text-muted-foreground">
              {snapshot.isTrial === true
                ? "Cancelling ends your free trial, so you won't be charged."
                : snapshot.isTrial === false
                  ? "Cancelling stops the renewal. You keep everything until the end of the period you've already paid for."
                  : "Cancelling stops the renewal, and if you're still in your free trial you won't be charged. Anything you've already paid for stays yours until the end of that period."}
            </p>
            <AlertDialog>
              <AlertDialogTrigger
                render={
                  <Button variant="outline" disabled={isCancelling}>
                    {isCancelling && <Loader2 className="h-4 w-4 animate-spin" />}
                    Cancel subscription
                  </Button>
                }
              />
              <AlertDialogContent>
                <AlertDialogHeader>
                  <AlertDialogTitle>Cancel your subscription?</AlertDialogTitle>
                  <AlertDialogDescription>
                    {snapshot.isTrial === true
                      ? `Your free trial won't convert, so you won't be charged for ${tierLabel(snapshot.tier)}.`
                      : snapshot.isTrial === false
                        ? `It won't renew, and you'll keep ${tierLabel(snapshot.tier)} until the end of the period you've paid for.`
                        : `It won't renew. If you're still in your free trial you won't be charged; otherwise you keep ${tierLabel(snapshot.tier)} until the end of the period you've paid for.`}
                    {" "}
                    If you&apos;re connected to a partner, they&apos;re covered by your subscription
                    too and will lose it at the same time.
                  </AlertDialogDescription>
                </AlertDialogHeader>
                <AlertDialogFooter>
                  <AlertDialogCancel>Keep it</AlertDialogCancel>
                  <AlertDialogAction onClick={handleCancel}>Cancel subscription</AlertDialogAction>
                </AlertDialogFooter>
              </AlertDialogContent>
            </AlertDialog>
          </>
        )}

        {control.kind === "web" && (requested || snapshot.willRenew === false) && (
          <p className="text-sm text-muted-foreground">
            This subscription won&apos;t renew, so there&apos;s nothing more to pay. You keep{" "}
            {tierLabel(snapshot.tier)} until the end of the period you&apos;ve paid for.
          </p>
        )}

        {control.kind === "elsewhere" && (
          <>
            <p className="text-sm text-muted-foreground">
              You bought this through {control.storeLabel}, so it&apos;s managed there — we
              can&apos;t cancel it for you from here.
            </p>
            {control.appleLink && (
              <Button variant="outline" render={
                <a href={APPLE_SUBSCRIPTIONS_URL} target="_blank" rel="noopener noreferrer">
                  Manage in the App Store
                  <ExternalLink className="h-4 w-4" />
                </a>
              } />
            )}
          </>
        )}

        {control.kind === "unknown" && (
          // Deliberately offers nothing. A subscription we cannot place is one we cannot promise to
          // cancel, and a button that might silently fail is worse than a sentence that admits it.
          <p className="text-sm text-muted-foreground">
            You&apos;re subscribed, but we can&apos;t tell from here where it was bought — so we
            can&apos;t safely cancel it for you. Email{" "}
            <a href="mailto:support@twofoldapp.com.au" className="underline">
              support@twofoldapp.com.au
            </a>{" "}
            and we&apos;ll sort it out.
          </p>
        )}
      </CardContent>
    </Card>
  );
}

function planSummary(snapshot: SubscriptionSnapshot): string {
  if (!snapshot.active) return "Free plan";
  // A trial says so instead of "since September 2026", which reads as a settled subscription and is
  // the one thing somebody on day two of a trial most needs to know about their own account. Only on
  // a positive `true`, for the same reason the badge is: an unknown falls through to the date.
  if (snapshot.isTrial === true) return `${tierLabel(snapshot.tier)}, free trial`;
  if (!snapshot.startedAt) return `${tierLabel(snapshot.tier)}, active`;
  const started = new Date(snapshot.startedAt);
  if (Number.isNaN(started.getTime())) return `${tierLabel(snapshot.tier)}, active`;
  return `${tierLabel(snapshot.tier)} since ${started.toLocaleDateString(undefined, {
    year: "numeric",
    month: "long",
  })}`;
}
