"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { parseSubscriptionHistory } from "@/lib/account/subscription";
import { fetchCustomerInfo } from "@/lib/marketing/billing";
import { anySaysYes, customerHasSubscribed, withTimeout, type TrialStanding } from "@/lib/marketing/trialEligibility";

/** How long RevenueCat gets before the database's answer stands on its own. */
const REVENUECAT_TIMEOUT_MS = 5000;

/**
 * Has this signed-in person ever subscribed, in the app or on the web?
 *
 * Three sources, because each has a blind spot the others cover:
 *
 * - `my_subscription_history()` (20261111001000): the append-only event log. Remembers a lapsed
 *   subscription that `profiles` has forgotten, but only reaches back to 20260926000000.
 * - `profiles.subscription_active`: right now, about both stores and both id spellings.
 * - RevenueCat CustomerInfo under the uppercase id the app uses: the whole history, however old,
 *   App Store included - but blind to the web customers created under the old lowercase spelling
 *   (see `revenueCatAppUserId`), which the database covers.
 *
 * Any one saying yes is enough. None saying yes - including every source failing - is "new", which
 * is what the page said before this existed; RevenueCat's checkout is the final word either way.
 */
export async function resolveTrialStanding(userId: string): Promise<"new" | "returning"> {
  const supabase = createClient();

  const fromLog = (async () => {
    const { data, error } = await supabase.rpc("my_subscription_history");
    if (error) return null;
    return parseSubscriptionHistory(data).everSubscribed;
  })();

  const fromProfile = (async () => {
    const { data, error } = await supabase.from("profiles").select("subscription_active").eq("id", userId).maybeSingle();
    if (error) return null;
    return data?.subscription_active === true;
  })();

  const fromRevenueCat = withTimeout(
    fetchCustomerInfo(userId).then((info) => (info ? customerHasSubscribed(info) : null)),
    REVENUECAT_TIMEOUT_MS,
    null
  );

  return (await anySaysYes([fromLog, fromProfile, fromRevenueCat])) ? "returning" : "new";
}

/**
 * The visitor's trial standing for rendering.
 *
 * `userId` is undefined while auth is still resolving and null when signed out; both render as
 * `signed-out`, which is also what the server rendered, so a signed-out visitor never sees the copy
 * change. A signed-in one goes through `checking`, where neither the trial nor "Resubscribe" is
 * claimed, rather than flashing a trial they will not get.
 */
export function useTrialStanding(userId: string | null | undefined): TrialStanding {
  const [resolved, setResolved] = useState<{ userId: string; standing: "new" | "returning" } | null>(null);

  useEffect(() => {
    if (!userId) return;
    let cancelled = false;
    resolveTrialStanding(userId).then((standing) => {
      if (!cancelled) setResolved({ userId, standing });
    });
    return () => {
      cancelled = true;
    };
  }, [userId]);

  if (!userId) return "signed-out";
  // Keyed by user, so signing in as somebody else never shows the previous person's answer.
  return resolved?.userId === userId ? resolved.standing : "checking";
}
