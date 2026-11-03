import { afterEach, describe, expect, it, vi } from "vitest";
import { daysAgo, dayMonth, emailTimestamp, longDate, shortDate, shortDateTime } from "./format";

// 14:30 UTC on 12 October is 01:30 on 13 October in Melbourne (AEDT, UTC+11). A formatter with no
// zone, run on a server in UTC (Vercel), says the 12th.
const MELBOURNE_SMALL_HOURS = "2026-10-12T14:30:00Z";

describe("console date formats", () => {
  it("use Melbourne's date, not the server's", () => {
    expect(shortDate(MELBOURNE_SMALL_HOURS)).toBe("13 Oct 2026");
    expect(longDate(MELBOURNE_SMALL_HOURS)).toBe("13 October 2026");
    expect(dayMonth(MELBOURNE_SMALL_HOURS)).toBe("13 Oct");
  });

  it("include a Melbourne time", () => {
    expect(shortDateTime(MELBOURNE_SMALL_HOURS)).toMatch(/^13 Oct 2026, 1:30\s?am$/);
  });

  it("show a dash, or nothing, for a missing or unreadable value", () => {
    expect(shortDate(null)).toBe("-");
    expect(longDate("not a date")).toBe("-");
    expect(dayMonth(undefined)).toBe("-");
    expect(daysAgo(null)).toBeNull();
  });
});

describe("emailTimestamp", () => {
  it("names its zone, so a visitor isn't shown UTC as if it were local", () => {
    expect(emailTimestamp(new Date(MELBOURNE_SMALL_HOURS))).toMatch(/^13 Oct 2026, 1:30\s?am AEDT$/);
  });
});

describe("daysAgo", () => {
  afterEach(() => vi.useRealTimers());

  it("counts whole days back from now", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-10-20T00:00:00Z"));
    expect(daysAgo("2026-10-19T23:00:00Z")).toBe("today");
    expect(daysAgo("2026-10-18T23:00:00Z")).toBe("yesterday");
    expect(daysAgo("2026-10-10T00:00:00Z")).toBe("10 days ago");
  });
});
