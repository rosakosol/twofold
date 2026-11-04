import type { LivePrices } from "@/lib/marketing/billing";
import { PLANS, type PlanId } from "@/lib/marketing/config";

// Figures the plan cards show, resolved against the live offering where possible.
//
// The Stripe product behind each RevenueCat package is what is actually charged, and only it knows
// the buyer's currency - a visitor in London was being shown "$9.99" and then charged in GBP at a
// number the page never displayed. So the live price wins wherever it is available, and PLANS'
// numbers (in FALLBACK_CURRENCY) stand in for a cold start or a RevenueCat outage.
//
// Every figure is derived here from an amount and a currency code, never from a label string. The
// per-month, per-person and savings figures used to be hand-maintained alongside the prices, and
// then regex-parsed out of them - which only worked while every price looked like "$9.99". "9,99 €"
// halved to "9,99 €4.99"-style nonsense, and a price change in Stripe could leave "$5.00/mo" or
// "Save 50%" quietly describing the old one.

/** An amount as RevenueCat reports it: $9.99 is 9_990_000 micros. */
export interface Money {
  amountMicros: number;
  /** ISO 4217. */
  currency: string;
}

/**
 * The currency PLANS' numbers are in, and what the products in RevenueCat are priced in by default.
 * A visitor shown the fallback is shown it as this, explicitly - see formatMoney.
 */
export const FALLBACK_CURRENCY = "AUD";

/**
 * Who is looking, as far as currency display cares: the locale numbers are formatted in, and the
 * regions we have reason to think they are in.
 */
export interface Viewer {
  locale?: string;
  regions: string[];
}

/**
 * The region a time zone is in, for the few zones that settle a "$" question on their own.
 *
 * Only Australia and New Zealand, because they are the cases the locale gets wrong most often - an
 * Australian on an "en-US" browser is common - and their zones name only them. "America/…" spans
 * the US, Canada and Mexico, so it says nothing the locale doesn't.
 */
function regionOfTimeZone(timeZone: string | undefined): string | null {
  if (!timeZone) return null;
  if (timeZone.startsWith("Australia/")) return "AU";
  if (timeZone === "Pacific/Auckland" || timeZone === "Pacific/Chatham") return "NZ";
  return null;
}

/** "en-AU" -> "AU"; "en" -> "US", the region CLDR assumes for it. Null when the tag is unusable. */
export function regionOfLocale(locale: string | undefined): string | null {
  if (!locale) return null;
  try {
    return new Intl.Locale(locale).maximize().region ?? null;
  } catch {
    return null;
  }
}

/** A viewer from explicit parts. Exists so the tests can say exactly who is looking. */
export function viewerFor(locale: string | undefined, timeZone?: string): Viewer {
  const regions = [regionOfLocale(locale), regionOfTimeZone(timeZone)].filter((r): r is string => r !== null);
  return { locale, regions };
}

/**
 * The browser's own viewer: the locale every number on the page is formatted in (what
 * `Intl.NumberFormat` resolves `undefined` to, normally `navigator.language`) and the time zone.
 * Only meaningful in the browser - on the server it describes the machine, which is why the cards
 * render a placeholder there rather than a figure (see PlanCard).
 */
export function browserViewer(): Viewer {
  const locale = new Intl.NumberFormat().resolvedOptions().locale;
  const timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone;
  return viewerFor(locale, timeZone);
}

/**
 * Currencies that are written with a bare "$" somewhere, the regions they are the local money of,
 * and the unambiguous prefix to write them with everywhere else.
 */
const DOLLARS: Record<string, { prefix: string; regions: string[] }> = {
  AUD: { prefix: "A$", regions: ["AU", "CX", "CC", "NF", "KI", "NR", "TV"] },
  USD: { prefix: "US$", regions: ["US", "PR", "GU", "VI", "AS", "MP", "UM", "EC", "SV", "TL", "FM", "MH", "PW", "BQ", "TC", "VG"] },
  CAD: { prefix: "CA$", regions: ["CA"] },
  NZD: { prefix: "NZ$", regions: ["NZ", "CK", "NU", "PN", "TK"] },
  SGD: { prefix: "S$", regions: ["SG"] },
  HKD: { prefix: "HK$", regions: ["HK"] },
  MXN: { prefix: "MX$", regions: ["MX"] },
};

/** Whether `currency` is the money of a region the viewer is in. */
export function isLocalCurrency(currency: string, viewer: Viewer): boolean {
  const regions = DOLLARS[currency]?.regions;
  return regions ? viewer.regions.some((r) => regions.includes(r)) : false;
}

function numberFormat(locale: string | undefined, currency: string, currencyDisplay: "narrowSymbol" | "symbol") {
  return new Intl.NumberFormat(locale, { style: "currency", currency, currencyDisplay });
}

/**
 * Formats an amount for this viewer, rather than using RevenueCat's `formattedPrice`.
 *
 * The rule: **a bare "$" only for the viewer's own dollar; every other dollar says which it is.**
 *
 * - The narrow symbol by default. An Australian sees AUD as "$9.99", which is how the site has
 *   always priced itself to them - the default display's "A$9.99" reads as a foreign-currency
 *   warning to somebody paying in their own money. Distinct symbols stay as they are: GBP "£",
 *   EUR "€", JPY "¥".
 * - But "$" alone is AUD, USD, CAD and NZD at once. So when the narrow symbol comes out as a bare
 *   "$" and the currency is not the viewer's own (isLocalCurrency), it is disambiguated: the
 *   locale's own symbol where that already says which dollar ("$US" in French), otherwise the
 *   explicit prefix in DOLLARS ("A$", "US$", "CA$", "NZ$"), otherwise the locale's standard form,
 *   which falls back to the ISO code.
 *
 * "Own" is decided by the locale's region and, for Australia and New Zealand, the time zone (see
 * regionOfTimeZone). Not by the currency RevenueCat chose: it picks one from the visitor's IP, and
 * falls back to AUD for a country with no price of its own, so AUD is not evidence of Australia.
 *
 * Null for a currency code Intl does not recognise; callers have something to fall back to.
 */
export function formatMoney(money: Money, viewer: Viewer = browserViewer()): string | null {
  const { currency } = money;
  const amount = money.amountMicros / 1_000_000;

  let parts: Intl.NumberFormatPart[];
  try {
    parts = numberFormat(viewer.locale, currency, "narrowSymbol").formatToParts(amount);
  } catch {
    // An engine without `narrowSymbol` throws rather than degrades; the standard symbol is always
    // explicit about which dollar it is. An unknown currency code throws here too.
    try {
      return numberFormat(viewer.locale, currency, "symbol").format(amount);
    } catch {
      return null;
    }
  }

  const symbol = parts.find((p) => p.type === "currency")?.value;
  if (symbol !== "$" || isLocalCurrency(currency, viewer)) return parts.map((p) => p.value).join("");

  const standard = numberFormat(viewer.locale, currency, "symbol");
  const standardSymbol = standard.formatToParts(amount).find((p) => p.type === "currency")?.value ?? "";
  const explicit = standardSymbol.includes("$") && standardSymbol.trim() !== "$" ? standardSymbol : DOLLARS[currency]?.prefix;
  if (!explicit) return standard.format(amount);
  return parts.map((p) => (p.type === "currency" ? explicit : p.value)).join("");
}

/**
 * "Australian dollars", "British pounds", "euros": the currency's name in running English, for the
 * line under the pricing cards. The site is written in English, so the name is too, whatever locale
 * the numbers are formatted in.
 */
export function currencyName(currency: string): string {
  try {
    const parts = new Intl.NumberFormat("en", { style: "currency", currency, currencyDisplay: "name" }).formatToParts(2);
    return parts.find((p) => p.type === "currency")?.value ?? currency;
  } catch {
    return currency;
  }
}

/**
 * `money` divided by `by`, rounded to the currency's smallest unit.
 *
 * Rounded in that unit rather than left to the formatter, so $19.99 halves to $10.00 instead of a
 * float's $9.99, and yen are never split into fractions the formatter then rounds differently.
 */
export function divideMoney(money: Money, by: number): Money {
  let digits = 2;
  try {
    digits = new Intl.NumberFormat("en", { style: "currency", currency: money.currency }).resolvedOptions().maximumFractionDigits ?? 2;
  } catch {
    // Unknown code: two decimals, the common case.
  }
  const unit = 10 ** (6 - digits);
  return { amountMicros: Math.round(money.amountMicros / by / unit) * unit, currency: money.currency };
}

/**
 * What yearly saves against paying monthly, as a whole percent. Null when either figure is
 * missing or the saving rounds to nothing, so the caller can drop the pill rather than
 * advertise "Save 0%". Unit-agnostic, since it is a ratio.
 */
export function savingPercent(monthly: number | undefined, yearly: number | undefined): number | null {
  if (!monthly || !yearly) return null;
  const saving = Math.round((1 - yearly / (monthly * 12)) * 100);
  return saving > 0 ? saving : null;
}

/** A plan's two prices, and whether they are the live ones. */
export interface PlanPrices {
  monthly: Money;
  yearly: Money;
  source: "live" | "fallback";
}

function fromPlans(planId: PlanId): PlanPrices {
  const plan = PLANS[planId];
  const money = (price: number): Money => ({ amountMicros: Math.round(price * 1_000_000), currency: FALLBACK_CURRENCY });
  return { monthly: money(plan.monthly.price), yearly: money(plan.yearly.price), source: "fallback" };
}

/**
 * The plan's prices from the live offering, or from PLANS when the offering lacks either of them.
 *
 * Both or neither: a card showing a live "£7.99" a month beside a fallback "A$59.99" a year would
 * be two currencies on one card, and its savings figure a ratio between them.
 */
export function planPrices(live: LivePrices, planId: PlanId): PlanPrices {
  const plan = PLANS[planId];
  const monthly = live[plan.monthly.packageId];
  const yearly = live[plan.yearly.packageId];
  if (!monthly || !yearly || monthly.currency !== yearly.currency) return fromPlans(planId);
  return {
    monthly: { amountMicros: monthly.amountMicros, currency: monthly.currency },
    yearly: { amountMicros: yearly.amountMicros, currency: yearly.currency },
    source: "live",
  };
}

/** Everything a plan card prints about money, already formatted for the viewer. */
export interface PlanFigures {
  /** The monthly price, for the two of you. */
  monthly: string;
  /** Half of it, for one of you. */
  monthlyEach: string;
  /** The yearly charge. */
  yearlyTotal: string;
  /** The yearly charge by month - the headline figure when Yearly is selected. */
  yearlyPerMonth: string;
  /** Half of that. */
  yearlyPerMonthEach: string;
  /** Null hides the "Save" pill. */
  saving: number | null;
  currency: string;
  source: "live" | "fallback";
}

/**
 * The card's figures for these prices. Null only if the currency cannot be formatted at all - a
 * live price in a code this engine does not know - in which case the caller falls back to PLANS.
 */
export function planFigures(prices: PlanPrices, viewer: Viewer = browserViewer()): PlanFigures | null {
  const perMonth = divideMoney(prices.yearly, 12);
  const monthly = formatMoney(prices.monthly, viewer);
  const monthlyEach = formatMoney(divideMoney(prices.monthly, 2), viewer);
  const yearlyTotal = formatMoney(prices.yearly, viewer);
  const yearlyPerMonth = formatMoney(perMonth, viewer);
  const yearlyPerMonthEach = formatMoney(divideMoney(perMonth, 2), viewer);
  if (!monthly || !monthlyEach || !yearlyTotal || !yearlyPerMonth || !yearlyPerMonthEach) return null;
  return {
    monthly,
    monthlyEach,
    yearlyTotal,
    yearlyPerMonth,
    yearlyPerMonthEach,
    saving: savingPercent(prices.monthly.amountMicros, prices.yearly.amountMicros),
    currency: prices.monthly.currency,
    source: prices.source,
  };
}

/** A plan's figures from the live offering, falling back to PLANS. */
export function figuresForPlan(live: LivePrices, planId: PlanId, viewer: Viewer = browserViewer()): PlanFigures {
  return planFigures(planPrices(live, planId), viewer) ?? planFigures(fromPlans(planId), viewer)!;
}

/**
 * Where the cards are with the live offering.
 *
 * - `loading`: nothing to show yet. The cards draw a placeholder, which is also what the server
 *   rendered - it cannot know the visitor's currency, so any figure it drew would be the wrong one
 *   for most visitors and would visibly change in front of them.
 * - `live`: the offering answered; `prices` is what this visitor will be charged.
 * - `fallback`: the offering answered with nothing, or took longer than LIVE_PRICE_TIMEOUT_MS (in
 *   useLivePrices.ts). The cards show PLANS' prices, labelled as the currency they are in (see
 *   formatMoney).
 */
export type LivePriceStatus = "loading" | "live" | "fallback";

/** Which of those it is, given what the query has answered. A late answer still beats the timeout. */
export function livePriceStatus(prices: LivePrices, answered: boolean, timedOut: boolean): LivePriceStatus {
  if (Object.keys(prices).length > 0) return "live";
  if (answered || timedOut) return "fallback";
  return "loading";
}
