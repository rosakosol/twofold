import nodemailer from "nodemailer";
import { SUPPORT_EMAIL } from "./companyInfo";

// Shared Zoho Mail SMTP transport — used by both /api/support and /api/waitlist, the same
// account/secrets already configured for the iOS app's submit-help-message Supabase function
// (see that function's own doc comment for the full DC/alias/app-password gotchas). One place
// to build this so both routes agree on host/port/from resolution instead of drifting apart.
/// What a message is, which is what decides the address it goes out as.
///
///   transactional - a receipt, a ticket, a password reset: anything the recipient asked for by
///     doing something. Sent as support@, the one address we advertise and the one
///     ingest-support-email turns replies into queue rows. Callers set their own `replyTo` when
///     the reply should go somewhere else, as /api/support does to reach the visitor.
///   announcement - a welcome or an announcement, where support@ reads like a helpdesk
///     acknowledging a ticket nobody filed. Sent as hello@, always with Reply-To: support@ so a
///     reply still reaches the queue rather than an address we never tell anyone to write to.
export type MailKind = "transactional" | "announcement";

export interface MailSender {
  from: string;
  replyTo?: string;
}

export interface ZohoMailer {
  transport: nodemailer.Transporter;
  /** The transactional From. Equivalent to `sender("transactional").from`. */
  from: string;
  /** The From/Reply-To pair for a kind of message — spread straight into `sendMail`. */
  sender: (kind: MailKind) => MailSender;
}

/** Throws if the required credentials aren't configured, so a caller fails loudly (or chooses
 * to catch and skip, like /api/waitlist does for its best-effort confirmation emails) rather
 * than silently no-op'ing on a typo'd env var name. */
export function createZohoTransport(): ZohoMailer {
  const user = process.env.ZOHO_SMTP_USER;
  const pass = process.env.ZOHO_SMTP_PASSWORD;
  if (!user || !pass) {
    throw new Error("Zoho SMTP credentials are not configured (ZOHO_SMTP_USER/ZOHO_SMTP_PASSWORD)");
  }
  const host = process.env.ZOHO_SMTP_HOST ?? "smtp.zoho.com.au";
  const port = Number(process.env.ZOHO_SMTP_PORT ?? "465");
  const from = process.env.ZOHO_FROM_ADDRESS ?? user;
  // Falls back to the transactional address rather than to a hardcoded hello@, so the split only
  // takes effect once the alias exists and is verified in Zoho. An unverified From is rejected
  // outright by Zoho, which would turn a welcome email into a silent failure; defaulting to the
  // address we know works means setting this variable is what switches the behaviour on.
  const announcementFrom = process.env.ZOHO_ANNOUNCEMENT_FROM_ADDRESS ?? from;

  const transport = nodemailer.createTransport({
    host,
    port,
    secure: port === 465,
    auth: { user, pass },
  });

  // Reply-To is set even when the two addresses are the same. Redundant in that case and
  // harmless, and it means the guarantee holds whichever alias the variable names: a reply to an
  // announcement reaches the support queue.
  const sender = (kind: MailKind): MailSender =>
    kind === "announcement" ? { from: announcementFrom, replyTo: SUPPORT_EMAIL } : { from };

  return { transport, from, sender };
}
