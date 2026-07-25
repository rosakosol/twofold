import nodemailer from "nodemailer";

// Shared Zoho Mail SMTP transport — used by both /api/support and /api/waitlist, the same
// account/secrets already configured for the iOS app's submit-help-message Supabase function
// (see that function's own doc comment for the full DC/alias/app-password gotchas). One place
// to build this so both routes agree on host/port/from resolution instead of drifting apart.
export interface ZohoMailer {
  transport: nodemailer.Transporter;
  from: string;
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
  const host = process.env.ZOHO_SMTP_HOST ?? "smtp.zoho.com";
  const port = Number(process.env.ZOHO_SMTP_PORT ?? "465");
  const from = process.env.ZOHO_FROM_ADDRESS ?? user;

  const transport = nodemailer.createTransport({
    host,
    port,
    secure: port === 465,
    auth: { user, pass },
  });

  return { transport, from };
}
