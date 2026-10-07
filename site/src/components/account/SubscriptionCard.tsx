"use client";

import { useEffect, useState } from "react";
import { toast } from "sonner";
import {
  ArrowLeftRight,
  CalendarClock,
  CheckCircle2,
  ExternalLink,
  HeartHandshake,
  Loader2,
  Store,
  XCircle,
} from "lucide-react";
import { StatusPill } from "@/components/site/StatusPill";
import { APP_STORE_URL } from "@/lib/marketing/config";
import { fetchCustomerInfo } from "@/lib/marketing/billing";
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
  endedBadgeLabel,
  longDate,
  renewalLine,
  subscriptionControl,
  tierLabel,
  type SubscriptionHistory,
  type SubscriptionSnapshot,
} from "@/lib/account/subscription";

/**
 * What this offers depends entirely on where the subscription was bought, which is why
 * `subscription_store` exists. An App Store subscription is Apple's and there is no API that ends
 * one; showing a cancel button for it would either do nothing or claim to have stopped a charge
 * that is still coming. So that case gets Apple's own settings link and an honest sentence.
 */
export function SubscriptionCard({
  snapshot,
  history,
  userId,
}: {
  snapshot: SubscriptionSnapshot;
  history: SubscriptionHistory;
  /** For RevenueCat's billing page link, which a web subscription changes plan on. */
  userId: string;
}) {
  const control = subscriptionControl(snapshot);
  // RevenueCat's own management page for a web subscription: cancelling, the card, receipts, and
  // moving between Plus and Premium once those paths are set up in the RevenueCat dashboard
  // (Product catalog, Subscription changes). Only fetched for a web subscription; null until it
  // arrives, or if it cannot be had, when the card points at the receipt emails instead.
  const [billingUrl, setBillingUrl] = useState<string | null>(null);
  useEffect(() => {
    if (control.kind !== "web") return;
    let cancelled = false;
    fetchCustomerInfo(userId).then((info) => {
      if (!cancelled) setBillingUrl(info?.managementURL ?? null);
    });
    return () => {
      cancelled = true;
    };
  }, [control.kind, userId]);
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

  const status = snapshot.active ? (
    <StatusPill tone="success" icon={<CheckCircle2 />}>
      {snapshot.isTrial === true ? "Free trial" : "Active"}
    </StatusPill>
  ) : history.everSubscribed ? (
    <StatusPill tone="error" icon={<XCircle />}>
      {endedBadgeLabel(history)}
    </StatusPill>
  ) : null;

  return (
    <section className="account-card" aria-labelledby="subscription-title">
      <div className="account-card-head">
        <h2 id="subscription-title">Subscription</h2>
        {status}
      </div>

      {control.kind === "none" ? (
        /* No free plan to be "on". For somebody whose subscription has ended, the useful thing is
           that fact and its date. `endedAt` is null for an ending that was never recorded, and a
           guessed date is worse than none. */
        !history.everSubscribed ? (
          <>
            <p className="account-plan">No subscription</p>
            <p className="account-muted">You don&apos;t have a subscription.</p>
            <div className="account-actions">
              <a className="btn btn-primary" href="/pricing">
                See plans
              </a>
            </div>
          </>
        ) : (
          <>
            <p className="account-plan">
              {history.lastTier ? tierLabel(history.lastTier) : "Twofold"}{" "}
              {history.endedReason === "lapsed" ? "lapsed" : "ended"}
              {longDate(history.endedAt) ? ` on ${longDate(history.endedAt)}` : ""}
            </p>
            <p className="account-muted">
              {history.endedReason === "lapsed" ? "A payment didn't go through. " : ""}
              Resubscribe to get access to all of Twofold&apos;s features in the app again.
            </p>
            <ul className="account-rows">
              <li>
                <span className="account-row-icon" aria-hidden>
                  <HeartHandshake />
                </span>
                <span>
                  <strong>Your trips and memories are still there</strong>
                  They stay exactly where they are. You can still open the app, read everything and export it;
                  adding new things needs a subscription.
                </span>
              </li>
            </ul>
            <div className="account-actions">
              <a className="btn btn-primary" href="/pricing">
                Resubscribe
              </a>
              <a className="btn btn-secondary" href="/pricing#compare">
                See plans
              </a>
            </div>
          </>
        )
      ) : (
        <>
          <p className="account-plan">{tierLabel(snapshot.tier)}</p>
          <ul className="account-rows">
            {/* When the next payment is, or when access runs out, whoever sells it. */}
            {renewalLine(snapshot) && (
              <li>
                <span className="account-row-icon" aria-hidden>
                  <CalendarClock />
                </span>
                <span>
                  <strong>{renewalLine(snapshot)}</strong>
                  {control.kind === "web" && (requested || snapshot.willRenew === false)
                    ? `This subscription won't renew, so there's nothing more to pay. You keep ${tierLabel(snapshot.tier)} until the end of the period you've paid for.`
                    : snapshot.isTrial === true
                      ? "Cancelling ends your free trial, so you won't be charged."
                      : snapshot.isTrial === false
                        ? "Cancelling stops the renewal. You keep everything until the end of the period you've already paid for."
                        : "Cancelling stops the renewal, and if you're still in your free trial you won't be charged. Anything you've already paid for stays yours until the end of that period."}
                </span>
              </li>
            )}
            <li>
              <span className="account-row-icon" aria-hidden>
                <Store />
              </span>
              <span>
                {control.kind === "web" ? (
                  <>
                    <strong>Bought on the website</strong>
                    So you can cancel it here.
                  </>
                ) : control.kind === "elsewhere" ? (
                  <>
                    <strong>Bought through {control.storeLabel}</strong>
                    So {control.storeLabel} handles cancelling, changing plan and your receipts. A subscription
                    cancelled there stops renewing everywhere, including in the app.
                  </>
                ) : control.kind === "grant" ? (
                  <>
                    <strong>Given to you</strong>
                    It wasn&apos;t bought, so there&apos;s nothing to pay and nothing to cancel.
                  </>
                ) : (
                  <>
                    <strong>We can&apos;t tell where this was bought</strong>
                    So we can&apos;t safely cancel it for you. Email{" "}
                    <a href="mailto:support@twofoldapp.com.au">support@twofoldapp.com.au</a> and we&apos;ll sort it
                    out.
                  </>
                )}
              </span>
            </li>
            {(control.kind === "web" || control.kind === "elsewhere") && (
              <li>
                <span className="account-row-icon" aria-hidden>
                  <ArrowLeftRight />
                </span>
                <span>
                  <strong>Changing plan</strong>
                  {/* Where it was bought is where it changes: a web subscription on its billing page,
                      an App Store one in the app. */}
                  {control.kind === "web"
                    ? billingUrl
                      ? "Move between Plus and Premium on your billing page."
                      : "Move between Plus and Premium from the billing page linked in your receipt emails."
                    : "Move between Plus and Premium from the subscription screen in the app."}
                </span>
              </li>
            )}
          </ul>

          <div className="account-actions">
            {control.kind === "web" && billingUrl && (
              <a className="btn btn-secondary" href={billingUrl} target="_blank" rel="noopener noreferrer">
                Change plan
                <ExternalLink aria-hidden />
              </a>
            )}
            {control.kind === "web" && !requested && snapshot.willRenew !== false && (
              <AlertDialog>
                <AlertDialogTrigger
                  render={
                    <button type="button" className="btn btn-secondary" disabled={isCancelling}>
                      {isCancelling && <Loader2 className="h-4 w-4 animate-spin" aria-hidden />}
                      Cancel subscription
                    </button>
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
                          : `It won't renew. If you're still in your free trial you won't be charged; otherwise you keep ${tierLabel(snapshot.tier)} until the end of the period you've paid for.`}{" "}
                      If you&apos;re connected to a partner, they&apos;re covered by your subscription too and will lose it
                      at the same time.
                    </AlertDialogDescription>
                  </AlertDialogHeader>
                  <AlertDialogFooter>
                    <AlertDialogCancel>Keep it</AlertDialogCancel>
                    <AlertDialogAction onClick={handleCancel}>Cancel subscription</AlertDialogAction>
                  </AlertDialogFooter>
                </AlertDialogContent>
              </AlertDialog>
            )}
            {control.kind === "elsewhere" && control.appleLink && (
              <a className="btn btn-secondary" href={APPLE_SUBSCRIPTIONS_URL} target="_blank" rel="noopener noreferrer">
                Manage in the App Store
                <ExternalLink aria-hidden />
              </a>
            )}
            <a className="btn btn-primary" href={APP_STORE_URL} data-appstore-link>
              Open Twofold
            </a>
          </div>
        </>
      )}
    </section>
  );
}
