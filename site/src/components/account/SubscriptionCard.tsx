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
        "We couldn't cancel your subscription just now, so nothing has changed — you're still subscribed. Please try again, or email hello@twofoldapp.com.au.",
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
          {snapshot.active && <Badge variant="secondary">{tierLabel(snapshot.tier)}</Badge>}
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
            <p className="text-sm text-muted-foreground">
              Cancelling stops the renewal. You keep everything until the end of the period
              you&apos;ve already paid for.
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
                    It won&apos;t renew, and you&apos;ll keep {tierLabel(snapshot.tier)} until the
                    end of the period you&apos;ve paid for. If you&apos;re connected to a partner,
                    they&apos;re covered by your subscription too and will lose it at the same time.
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
            This subscription won&apos;t renew. You keep {tierLabel(snapshot.tier)} until the end of
            the period you&apos;ve paid for.
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
            <a href="mailto:hello@twofoldapp.com.au" className="underline">
              hello@twofoldapp.com.au
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
  if (!snapshot.startedAt) return `${tierLabel(snapshot.tier)}, active`;
  const started = new Date(snapshot.startedAt);
  if (Number.isNaN(started.getTime())) return `${tierLabel(snapshot.tier)}, active`;
  return `${tierLabel(snapshot.tier)} since ${started.toLocaleDateString(undefined, {
    year: "numeric",
    month: "long",
  })}`;
}
