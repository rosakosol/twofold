import type { CustomerInfo } from "@revenuecat/purchases-js";

/**
 * Whether the free trial is something we can honestly offer the person looking at the page.
 *
 * - `signed-out`: we cannot know, and most visitors here have never subscribed, so the trial is
 *   advertised. This is also what renders on the server and while auth is still resolving.
 * - `checking`: signed in, history not read yet. Neither claim is made.
 * - `new`: signed in, and nothing we can see says they have ever subscribed.
 * - `returning`: signed in, and they have subscribed before - in the app or here.
 *
 * Returning subscribers were told "Start 14-day free trial" because the label was a constant. It
 * still matters what RevenueCat's checkout then does (see the product's trial eligibility in the
 * dashboard), but the page has no business promising a trial to somebody who has had one.
 */
export type TrialStanding = "signed-out" | "checking" | "new" | "returning";

/** Code-owned CTA copy. No Sanity field carries any of this; the trial length is the product's. */
export const PLAN_CTA = {
  trial: "Start 14-day free trial",
  /** Somebody who has subscribed before, in the app or on the web. */
  returning: "Resubscribe",
  /** Neutral, and true for everybody: while checking, and when the product carries no trial. */
  subscribe: "Subscribe",
} as const;

export function standingOffersTrial(standing: TrialStanding): boolean {
  return standing === "signed-out" || standing === "new";
}

/**
 * The plan card's button label.
 *
 * `liveTrial` is whether the package RevenueCat returned for this customer carries a free-trial
 * phase (`LivePrice.hasFreeTrial`), undefined until the offering has loaded. False wins over
 * everything: RevenueCat only returns the offers a customer is entitled to, so a package without a
 * trial phase is a checkout without a trial, whatever the standing says.
 */
export function planCtaLabel(standing: TrialStanding, liveTrial?: boolean): string {
  if (standing === "returning") return PLAN_CTA.returning;
  if (standing === "checking" || liveTrial === false) return PLAN_CTA.subscribe;
  return PLAN_CTA.trial;
}

/**
 * Whether this RevenueCat customer has ever held a subscription, active or long expired.
 *
 * Reads every map CustomerInfo has rather than trusting one: `entitlements.all` keeps expired
 * entitlements, and `subscriptionsByProductIdentifier` keeps every subscription product the customer
 * has bought in any store, including ones attached to no entitlement. App Store purchases are here
 * too, because the app logs in under the same (uppercase) id `billing.ts` configures.
 *
 * Not counted, because they are not a subscription anybody bought:
 * - `promotional` - a grant from us (or RevenueCat's own trial-extension tooling)
 * - `FAMILY_SHARED` - Apple Family Sharing, somebody else's purchase
 */
export function customerHasSubscribed(info: CustomerInfo): boolean {
  const entitlements = Object.values(info.entitlements?.all ?? {});
  if (entitlements.some((e) => e.store !== "promotional" && e.ownershipType !== "FAMILY_SHARED")) return true;

  const subscriptions = Object.values(info.subscriptionsByProductIdentifier ?? {});
  return subscriptions.some((s) => s.store !== "promotional" && s.ownershipType !== "FAMILY_SHARED");
}

/**
 * Resolves true as soon as any source says true; otherwise false once every source has answered.
 * A source that fails or answers null is simply not evidence either way.
 *
 * "First yes wins" so one slow source (RevenueCat, usually) does not hold the page in `checking`
 * when the database has already said they are returning.
 */
export function anySaysYes(sources: Promise<boolean | null>[]): Promise<boolean> {
  return new Promise((resolve) => {
    let remaining = sources.length;
    if (remaining === 0) resolve(false);
    for (const source of sources) {
      source
        .then((answer) => {
          if (answer === true) resolve(true);
        })
        .catch(() => {})
        .finally(() => {
          remaining -= 1;
          if (remaining === 0) resolve(false);
        });
    }
  });
}

/** `promise`, or `fallback` if it has not settled within `ms`. */
export function withTimeout<T>(promise: Promise<T>, ms: number, fallback: T): Promise<T> {
  return new Promise((resolve) => {
    const timer = setTimeout(() => resolve(fallback), ms);
    promise
      .then(resolve, () => resolve(fallback))
      .finally(() => clearTimeout(timer));
  });
}
