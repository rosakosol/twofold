import { describe, expect, it } from "vitest";
import type { LivePrice, LivePrices } from "./billing";
import {
  currencyName,
  divideMoney,
  figuresForPlan,
  formatMoney,
  isLocalCurrency,
  livePriceStatus,
  planPrices,
  regionOfLocale,
  viewerFor,
} from "./priceDisplay";

// Intl inserts U+00A0 / U+202F in some locales ("9,99 €"); compare on plain spaces.
const plain = (s: string | null) => s?.replace(/[  ]/g, " ") ?? null;
const money = (amount: number, currency: string) => ({ amountMicros: Math.round(amount * 1_000_000), currency });
const fmt = (amount: number, currency: string, locale: string, timeZone?: string) =>
  plain(formatMoney(money(amount, currency), viewerFor(locale, timeZone)));

const AU = viewerFor("en-AU", "Australia/Sydney");
const US = viewerFor("en-US", "America/New_York");
const UK = viewerFor("en-GB", "Europe/London");

function live(currency: string, amounts: [number, number, number, number], hasFreeTrial = true): LivePrices {
  const ids = ["plus_monthly", "plus_yearly", "premium_monthly", "premium_yearly"];
  return Object.fromEntries(
    ids.map((id, i): [string, LivePrice] => [
      id,
      { formattedPrice: "ignored", amountMicros: Math.round(amounts[i] * 1_000_000), currency, hasFreeTrial },
    ])
  );
}

describe("regionOfLocale", () => {
  it("reads the region, assuming CLDR's for a bare language", () => {
    expect(regionOfLocale("en-AU")).toBe("AU");
    expect(regionOfLocale("en")).toBe("US");
    expect(regionOfLocale("fr")).toBe("FR");
  });
  it("is null for nothing or nonsense", () => {
    expect(regionOfLocale(undefined)).toBeNull();
    expect(regionOfLocale("not a locale!")).toBeNull();
  });
});

describe("isLocalCurrency", () => {
  it("knows each dollar's own country", () => {
    expect(isLocalCurrency("AUD", viewerFor("en-AU"))).toBe(true);
    expect(isLocalCurrency("USD", viewerFor("en-US"))).toBe(true);
    expect(isLocalCurrency("CAD", viewerFor("fr-CA"))).toBe(true);
    expect(isLocalCurrency("AUD", viewerFor("en-US"))).toBe(false);
  });
  it("counts an Australian time zone as Australia, whatever the browser language", () => {
    expect(isLocalCurrency("AUD", viewerFor("en-US", "Australia/Perth"))).toBe(true);
    expect(isLocalCurrency("NZD", viewerFor("en-GB", "Pacific/Auckland"))).toBe(true);
    // America/... spans three dollars, so it decides nothing.
    expect(isLocalCurrency("CAD", viewerFor("en-US", "America/Toronto"))).toBe(false);
  });
});

describe("formatMoney", () => {
  it("writes the viewer's own dollar as a bare $", () => {
    expect(fmt(9.99, "AUD", "en-AU")).toBe("$9.99");
    expect(fmt(9.99, "USD", "en-US")).toBe("$9.99");
    expect(fmt(9.99, "CAD", "en-CA")).toBe("$9.99");
    expect(fmt(9.99, "NZD", "en-NZ")).toBe("$9.99");
  });

  it("says which dollar it is to everybody else", () => {
    expect(fmt(9.99, "AUD", "en-US")).toBe("A$9.99");
    expect(fmt(9.99, "AUD", "en-GB")).toBe("A$9.99");
    expect(fmt(9.99, "USD", "en-AU")).toBe("US$9.99");
    expect(fmt(9.99, "USD", "en-GB")).toBe("US$9.99");
    expect(fmt(9.99, "CAD", "en-AU")).toBe("CA$9.99");
    expect(fmt(9.99, "NZD", "en-US")).toBe("NZ$9.99");
  });

  it("keeps the locale's own word order and, where it has one, its own explicit symbol", () => {
    expect(fmt(9.99, "USD", "de-DE")).toBe("9,99 US$");
    expect(fmt(9.99, "AUD", "de-DE")).toBe("9,99 AU$");
    expect(fmt(9.99, "USD", "fr-FR")).toBe("9,99 $US");
  });

  it("treats an Australian on an en-US browser as Australian", () => {
    expect(fmt(9.99, "AUD", "en-US", "Australia/Melbourne")).toBe("$9.99");
  });

  it("leaves currencies with their own sign alone", () => {
    expect(fmt(7.99, "GBP", "en-GB")).toBe("£7.99");
    expect(fmt(7.99, "GBP", "en-US")).toBe("£7.99");
    expect(fmt(8.99, "EUR", "en-AU")).toBe("€8.99");
    expect(fmt(8.99, "EUR", "de-DE")).toBe("8,99 €");
    expect(fmt(1200, "JPY", "en-US")).toBe("¥1,200");
  });

  it("is null for a currency code Intl does not know", () => {
    expect(formatMoney(money(1, "XXXX"), AU)).toBeNull();
  });
});

describe("divideMoney", () => {
  it("rounds in the currency's smallest unit", () => {
    // A float would make 19.99 / 2 into 9.994999..., and the formatter would print $9.99.
    expect(divideMoney(money(19.99, "AUD"), 2)).toEqual(money(10, "AUD"));
    expect(divideMoney(money(59.99, "AUD"), 12)).toEqual(money(5, "AUD"));
    expect(divideMoney(money(1199, "JPY"), 2)).toEqual(money(600, "JPY"));
  });
});

describe("currencyName", () => {
  it("names the currency in running English", () => {
    expect(currencyName("AUD")).toBe("Australian dollars");
    expect(currencyName("GBP")).toBe("British pounds");
    expect(currencyName("USD")).toBe("US dollars");
  });
});

describe("figuresForPlan", () => {
  it("formats live prices for the viewer and derives every other figure from them", () => {
    const f = figuresForPlan(live("GBP", [7.99, 47.99, 15.99, 95.99]), "premium", UK);
    expect(f.source).toBe("live");
    expect(f.currency).toBe("GBP");
    expect(f.monthly).toBe("£15.99");
    expect(f.monthlyEach).toBe("£8.00");
    expect(f.yearlyTotal).toBe("£95.99");
    expect(f.yearlyPerMonth).toBe("£8.00");
    expect(f.yearlyPerMonthEach).toBe("£4.00");
    expect(f.saving).toBe(50);
  });

  it("halves comma-decimal prices correctly (the old label regex did not)", () => {
    const f = figuresForPlan(live("EUR", [8.99, 53.99, 17.99, 107.99]), "plus", viewerFor("de-DE"));
    expect(plain(f.monthly)).toBe("8,99 €");
    expect(plain(f.monthlyEach)).toBe("4,50 €");
  });

  describe("fallback (no live offering)", () => {
    it("shows PLANS' AUD prices as a bare $ to an Australian", () => {
      const f = figuresForPlan({}, "plus", AU);
      expect(f.source).toBe("fallback");
      expect(f.currency).toBe("AUD");
      expect(f.monthly).toBe("$9.99");
      expect(f.monthlyEach).toBe("$5.00");
      expect(f.yearlyTotal).toBe("$59.99");
      expect(f.yearlyPerMonth).toBe("$5.00");
      expect(f.saving).toBe(50);
    });

    it("marks them as AUD to anybody else, never as their own currency", () => {
      expect(figuresForPlan({}, "plus", US).monthly).toBe("A$9.99");
      expect(figuresForPlan({}, "premium", UK).monthly).toBe("A$19.99");
      expect(figuresForPlan({}, "premium", UK).yearlyPerMonth).toBe("A$10.00");
    });

    it("is used whole when the offering is missing either of a plan's packages", () => {
      const partial = live("GBP", [7.99, 47.99, 15.99, 95.99]);
      delete partial.plus_yearly;
      expect(planPrices(partial, "plus").source).toBe("fallback");
      expect(figuresForPlan(partial, "plus", UK).monthly).toBe("A$9.99");
      expect(figuresForPlan(partial, "premium", UK).monthly).toBe("£15.99");
    });

    it("is used when a live currency cannot be formatted", () => {
      expect(figuresForPlan(live("XXXX", [1, 2, 3, 4]), "plus", AU).monthly).toBe("$9.99");
    });
  });
});

describe("livePriceStatus", () => {
  it("is loading until the offering answers or the timeout passes", () => {
    expect(livePriceStatus({}, false, false)).toBe("loading");
  });
  it("is live as soon as there are prices, even after the timeout", () => {
    expect(livePriceStatus(live("USD", [1, 2, 3, 4]), true, true)).toBe("live");
  });
  it("falls back on an empty answer or a timeout", () => {
    expect(livePriceStatus({}, true, false)).toBe("fallback");
    expect(livePriceStatus({}, false, true)).toBe("fallback");
  });
});
