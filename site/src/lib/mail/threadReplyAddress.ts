import { SUPPORT_EMAIL } from "./companyInfo";

/**
 * The address a reply to a support conversation should go to: `support+t<token>@twofoldapp.com.au`.
 *
 * Zoho delivers plus-addressed mail to the support mailbox, ingest-support-email passes the To/Cc
 * through, and `private.token_from_address` reads the token back out, so mail sent here lands in
 * that conversation whatever its subject says. The console's own replies are addressed the same way
 * (supabase/functions/send-support-reply/compose.ts, `replyToAddress`).
 *
 * Null for anything that is not a token as the database issues them (ten hex characters, which is
 * also all the inbound matcher will read). The value reaches a mail header, so a malformed one is
 * refused rather than cleaned, and the caller falls back to plain support@.
 *
 * Whoever holds the token can post into the conversation, so the result belongs only in the Reply-To
 * of mail to the person the conversation is with.
 */
export function threadReplyAddress(token: string | null | undefined): string | null {
  if (!token || !/^[0-9a-f]{10}$/i.test(token)) return null;
  const at = SUPPORT_EMAIL.lastIndexOf("@");
  return `${SUPPORT_EMAIL.slice(0, at)}+t${token.toLowerCase()}${SUPPORT_EMAIL.slice(at)}`;
}
