"use client";

import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { queryKeys } from "@/lib/queries/queryKeys";
import { anonymousAppUserId, fetchLivePrices, type LivePrices } from "@/lib/marketing/billing";

const NO_PRICES: LivePrices = {};

/**
 * The live web offering's prices, for every surface that shows a plan card: /pricing and the home
 * page's pricing summary. One query, so the two can never disagree and a visitor going from one to
 * the other does not read the offering twice.
 *
 * `userId` is the signed-in Supabase user, or null for a visitor. Prices have to be on screen for
 * somebody who may never sign in, so null reads the offering under a throwaway anonymous id (see
 * `fetchLivePrices`); once a session appears it is read again under the real id, which is what any
 * per-customer pricing or trial eligibility keys off. The previous result stays on screen while
 * that happens, rather than the cards emptying for a moment.
 */
export function useLivePrices(userId: string | null, offeringId: string | null = null): LivePrices {
  const query = useQuery({
    queryKey: queryKeys.livePrices(offeringId, userId),
    queryFn: async () => {
      const appUserId = userId ?? (await anonymousAppUserId());
      if (!appUserId) return NO_PRICES;
      return fetchLivePrices(appUserId, offeringId ?? undefined);
    },
    placeholderData: keepPreviousData,
    // A price does not change while somebody reads the page. fetchLivePrices never throws, so
    // there is nothing to retry either.
    staleTime: 5 * 60 * 1000,
    retry: false,
  });
  return query.data ?? NO_PRICES;
}
