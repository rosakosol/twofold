import { SITE_URL } from "@/lib/mail/companyInfo";

/** The lists an email can be unsubscribed from (supabase/migrations/20261112000000). Account,
 *  security, billing and support mail is not one of them. */
export type EmailList = "product_news" | "feedback_updates" | "android_waitlist";

/** The page a person lands on from an email's unsubscribe link. It asks before changing anything,
 *  so a mail scanner that follows the link unsubscribes nobody. */
export function unsubscribeUrl(token: string, list: EmailList): string {
  return `${SITE_URL}/unsubscribe?token=${encodeURIComponent(token)}&list=${list}`;
}

/** Email preferences on the account page. */
export const PREFERENCES_URL = `${SITE_URL}/account#email`;

/**
 * The headers that give mail apps their own Unsubscribe button (RFC 2369 and RFC 8058). The POST
 * target unsubscribes at once, which one-click requires, and is only reached by a deliberate press
 * in the mail app, never by a scanner fetching links.
 */
export function listUnsubscribeHeaders(token: string, list: EmailList): Record<string, string> {
  const oneClick = `${SITE_URL}/api/unsubscribe?token=${encodeURIComponent(token)}&list=${list}`;
  return {
    "List-Unsubscribe": `<${oneClick}>`,
    "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
  };
}
