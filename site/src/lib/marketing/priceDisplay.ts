import type { LivePrice, LivePrices } from "@/lib/marketing/billing";

// Figures the pricing cards show, resolved against the live offering where possible.
//
// Three copies of every price exist: the Stripe product (what is actually charged), the Studio
// plan document, and PLANS in config.ts. Only the first is authoritative, and only the first
// knows the buyer's currency - a visitor in London was being shown "$9.99" and then charged in
// GBP at a number the page never displayed. So the live price wins wherever it is available,
// and the labels stay as the fallback for a cold start or a RevenueCat outage.
//
// The per-month and savings figures used to be hand-maintained alongside the prices. They are
// derived here instead, so changing a price in Stripe can't leave "$5.00/mo" or "Save 50%"
// quietly describing the old one.

/** Live price if the offering had one, otherwise the label already in the plan. */
export function priceLabelFor(live: LivePrices, packageId: string, fallback: string): string {
  const price = live[packageId];
  if (!price) return fallback;
  // RevenueCat's own formattedPrice is the last resort rather than the first choice — it is
  // the one that carries the "A$" prefix. See format() above.
  return format(price.amountMicros, price.currency) ?? price.formattedPrice ?? fallback;
}

/**
 * Formats an amount ourselves rather than using RevenueCat's `formattedPrice`.
 *
 * The products are priced in AUD, and the default currency display renders that as "A$9.99" —
 * accurate, but the site has always said "$9.99" and the prefix reads as a foreign-currency
 * warning to an Australian visitor. `narrowSymbol` drops it to "$" while leaving genuinely
 * distinct symbols alone: GBP stays "£", EUR stays "€", JPY stays "¥".
 *
 * Falls back through plain `symbol` before giving up, since `narrowSymbol` throws rather than
 * degrades on an engine that doesn't know it.
 */
function format(amountMicros: number, currency: string): string | null {
  const amount = amountMicros / 1_000_000;
  for (const currencyDisplay of ["narrowSymbol", "symbol"] as const) {
    try {
      return new Intl.NumberFormat(undefined, { style: "currency", currency, currencyDisplay }).format(amount);
    } catch {
      // An unrecognised currency code or display mode throws rather than degrading.
    }
  }
  return null;
}

/** A yearly plan's cost per month - the headline figure on the card when Yearly is selected. */
export function perMonthLabelFor(live: LivePrices, yearlyPackageId: string, fallback: string): string {
  const yearly = live[yearlyPackageId];
  if (!yearly) return fallback;
  return format(yearly.amountMicros / 12, yearly.currency) ?? fallback;
}

/**
 * What yearly saves against paying monthly, as a whole percent. Null when either figure is
 * missing or the saving rounds to nothing, so the caller can drop the pill rather than
 * advertise "Save 0%". Unit-agnostic - micros from the live offering and plain currency
 * amounts from PLANS both work, since it is a ratio.
 */
export function savingPercent(monthly: number | undefined, yearly: number | undefined): number | null {
  if (!monthly || !yearly) return null;
  const saving = Math.round((1 - yearly / (monthly * 12)) * 100);
  return saving > 0 ? saving : null;
}

/** The same figure from a pair of live prices. */
export function yearlySavingPercent(
  monthly: LivePrice | undefined,
  yearly: LivePrice | undefined
): number | null {
  return savingPercent(monthly?.amountMicros, yearly?.amountMicros);
}
