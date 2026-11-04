"use client";

import { useEffect, useState, useSyncExternalStore } from "react";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { queryKeys } from "@/lib/queries/queryKeys";
import { anonymousAppUserId, fetchLivePrices, type LivePrices } from "@/lib/marketing/billing";
import { livePriceStatus, previewCurrency, type LivePriceStatus } from "@/lib/marketing/priceDisplay";

const NO_PRICES: LivePrices = {};

/**
 * How long the cards hold a placeholder before settling for the fallback prices. Long enough for a
 * slow mobile connection to fetch the SDK and the offering, short enough that a RevenueCat outage
 * still leaves the page priced while somebody is reading it.
 */
export const LIVE_PRICE_TIMEOUT_MS = 4000;

export interface LivePriceState {
  prices: LivePrices;
  status: LivePriceStatus;
  /** The `?currency=` being previewed, if any - see previewCurrency. */
  previewing: string | null;
}

// `?currency=` read straight off the location rather than through useSearchParams, which would
// need a Suspense boundary around the home page's cards for a parameter only the owner ever sets.
// The server snapshot is null, matching the server render; the query key picks up the real value.
const noSubscription = () => () => {};
const readPreviewCurrency = () => previewCurrency(window.location.search);
const noPreviewOnServer = () => null;

/**
 * The live web offering's prices, for every surface that shows a plan card: /pricing and the home
 * page's pricing summary. One query, so the two can never disagree and a visitor going from one to
 * the other does not read the offering twice - the second page has its prices on first render.
 *
 * `userId` is the signed-in Supabase user, null for a visitor, and undefined while auth is still
 * resolving - in which case nothing is fetched yet, rather than configuring the SDK under an
 * anonymous id only to switch it a moment later. Prices have to be on screen for somebody who may
 * never sign in, so null reads the offering under a throwaway anonymous id (see `fetchLivePrices`);
 * a session appearing later reads it again under the real id, which is what trial eligibility keys
 * off. The previous result stays on screen while that happens.
 */
export function useLivePrices(userId: string | null | undefined, offeringId: string | null = null): LivePriceState {
  const previewing = useSyncExternalStore(noSubscription, readPreviewCurrency, noPreviewOnServer);

  const query = useQuery({
    queryKey: queryKeys.livePrices(offeringId, userId ?? null, previewing),
    enabled: userId !== undefined,
    queryFn: async () => {
      const appUserId = userId ?? (await anonymousAppUserId());
      if (!appUserId) return NO_PRICES;
      return fetchLivePrices(appUserId, offeringId ?? undefined, previewing ?? undefined);
    },
    placeholderData: keepPreviousData,
    // A price does not change while somebody reads the page. fetchLivePrices never throws, so
    // there is nothing to retry either.
    staleTime: 5 * 60 * 1000,
    retry: false,
  });

  // Started on mount, not when the query starts, so a slow auth check counts against it too.
  const [timedOut, setTimedOut] = useState(false);
  useEffect(() => {
    const timer = setTimeout(() => setTimedOut(true), LIVE_PRICE_TIMEOUT_MS);
    return () => clearTimeout(timer);
  }, []);

  const prices = query.data ?? NO_PRICES;
  return { prices, status: livePriceStatus(prices, query.data !== undefined, timedOut), previewing };
}
