/**
 * Dates for the console and the site's emails, in one locale and one zone.
 *
 * A fixed locale and zone rather than the viewer's, as on the Users list: half of these render on
 * the server and half in the browser, and a page where "Oct 12, 2026" sits beside "12/10/2026" is
 * the kind of noise that makes a support screen hard to read.
 */

const LOCALE = "en-AU";
const TIME_ZONE = "Australia/Melbourne";

function parse(value: string | null | undefined): Date | null {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

/** "12 Oct 2026", or "-" for nothing. */
export function shortDate(value: string | null | undefined): string {
  const date = parse(value);
  if (!date) return "-";
  return date.toLocaleDateString(LOCALE, { day: "numeric", month: "short", year: "numeric", timeZone: TIME_ZONE });
}

/** "12 Oct 2026, 3:04 pm", or "-" for nothing. */
export function shortDateTime(value: string | null | undefined): string {
  const date = parse(value);
  if (!date) return "-";
  return date.toLocaleString(LOCALE, {
    day: "numeric",
    month: "short",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
    timeZone: TIME_ZONE,
  });
}

/** "12 October 2026", or "-" for nothing. */
export function longDate(value: string | null | undefined): string {
  const date = parse(value);
  if (!date) return "-";
  return date.toLocaleDateString(LOCALE, { day: "numeric", month: "long", year: "numeric", timeZone: TIME_ZONE });
}

/** "12 Oct", for a column or a chart axis where the year is obvious. "-" for nothing. */
export function dayMonth(value: string | null | undefined): string {
  const date = parse(value);
  if (!date) return "-";
  return date.toLocaleDateString(LOCALE, { day: "numeric", month: "short", timeZone: TIME_ZONE });
}

/** "12 Oct 2026, 3:04 pm AEDT": a moment in an email, with its zone named. Emails were formatted
 *  in the server's zone, UTC on Vercel, with no label, and read as the recipient's local time. */
export function emailTimestamp(date: Date): string {
  return date.toLocaleString(LOCALE, {
    day: "numeric",
    month: "short",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
    timeZone: TIME_ZONE,
    timeZoneName: "short",
  });
}

/** "today", "yesterday", "3 days ago", "5 months ago". For the header, where the gist is enough
 *  and the exact date is one row below. */
export function daysAgo(value: string | null | undefined): string | null {
  const date = parse(value);
  if (!date) return null;
  const days = Math.floor((Date.now() - date.getTime()) / 86_400_000);
  if (days <= 0) return "today";
  if (days === 1) return "yesterday";
  if (days < 45) return `${days} days ago`;
  const months = Math.round(days / 30);
  if (months < 18) return `${months} months ago`;
  return `${Math.round(days / 365)} years ago`;
}
