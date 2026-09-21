import { NextResponse } from "next/server";
import { createZohoTransport } from "@/lib/mail/zoho";
import { renderTemplate, extractSubject } from "@/lib/mail/renderTemplate";
import { escapeHtml } from "@/lib/mail/escapeHtml";
import { SUPPORT_EMAIL, SITE_URL } from "@/lib/mail/companyInfo";
import { createClient } from "@/lib/supabase/server";
import { nullableArg } from "@/lib/db/nullableArg";

// Web counterpart to the iOS app's submit-help-message edge function
// (supabase/functions/submit-help-message) - same category list and same recipient
// (support@twofoldapp.com.au), sent via the same Zoho Mail SMTP account (see
// lib/mail/zoho.ts for the transport + required env vars). This one has to work for an
// anonymous site visitor with no Supabase session, so it can't reuse that function's
// Bearer-token-gated auth.
//
// Sends two emails per submission, using the templates in lib/mail/templates/ (see that
// folder's README.md for the full token list each one accepts):
//   - support-internal-alert.html -> support@ (the actual ticket)
//   - support-received.html -> the visitor (a receipt, so they know it landed)

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MAX_NAME_LENGTH = 200;

/// The caller's address as the platform reports it. `x-forwarded-for` is a list when there are
/// proxies in front; the first entry is the client. Falls back to a constant rather than to
/// nothing, so a request arriving without the header shares one bucket instead of being
/// unlimited — the failure direction matters more here than the precision.
function callerIP(request: Request): string {
  const forwarded = request.headers.get("x-forwarded-for");
  if (forwarded) return forwarded.split(",")[0]!.trim();
  return request.headers.get("x-real-ip")?.trim() || "unknown";
}

type RateLimitOutcome = "allowed" | "refused" | "unavailable";

/// Consumes every bucket, and refuses if any of them says no.
///
/// Returns `unavailable` rather than throwing when the database cannot be reached: a limiter
/// outage must not take the support form down with it. The caller decides what a degraded mode
/// means — here, the internal alert still goes and the caller-addressed receipt does not.
async function withinRateLimit(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  supabase: any,
  buckets: { bucket: string; subject: string; limit: number }[],
): Promise<RateLimitOutcome> {
  for (const { bucket, subject, limit } of buckets) {
    const { data, error } = await supabase.rpc("consume_anon_rate_limit", {
      p_bucket: bucket,
      p_subject: subject,
      p_limit: limit,
      p_window: "01:00:00",
    });
    if (error) {
      console.error(`[support] rate limit unavailable (${bucket}):`, error.message);
      return "unavailable";
    }
    if (data === false) return "refused";
  }
  return "allowed";
}

const SUPPORT_CATEGORIES = [
  "Account & Subscription",
  "Bug Report",
  "Flight Tracking",
  "Trips & Memories",
  "Game Issue",
  "Feature Request",
  "Feedback",
  "Other",
] as const;

const MAX_MESSAGE_LENGTH = 5000;

export async function POST(request: Request) {
  let body: { name?: string; email?: string; category?: string; message?: string; company?: string };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid request." }, { status: 400 });
  }

  // Honeypot: bots tend to fill every field. Pretend success so we don't tip them off.
  if (body.company) {
    return NextResponse.json({ ok: true });
  }

  const name = (body.name ?? "").trim();
  const email = (body.email ?? "").trim().toLowerCase();
  const category = (body.category ?? "").trim();
  const message = (body.message ?? "").trim();

  if (!email || !EMAIL_RE.test(email) || email.length > 320) {
    return NextResponse.json({ error: "Enter a valid email address." }, { status: 400 });
  }
  if (!SUPPORT_CATEGORIES.includes(category as (typeof SUPPORT_CATEGORIES)[number])) {
    return NextResponse.json({ error: "Choose a category." }, { status: 400 });
  }
  if (!message) {
    return NextResponse.json({ error: "Enter a message." }, { status: 400 });
  }
  if (message.length > MAX_MESSAGE_LENGTH) {
    return NextResponse.json({ error: "Message is too long." }, { status: 400 });
  }
  // `name` had no cap, unlike `message`. It reaches an email template.
  if (name.length > MAX_NAME_LENGTH) {
    return NextResponse.json({ error: "Name is too long." }, { status: 400 });
  }

  // Two buckets, because they fail differently. The email is trivially rotated — an attacker
  // picks a new recipient for each send, which is the whole point of a relay — so it is the IP
  // that has to carry the limit. The email bucket is the narrower one, and stops the same address
  // being mailed repeatedly from a rotating source.
  const supabase = await createClient();
  const ip = callerIP(request);
  const allowed = await withinRateLimit(supabase, [
    { bucket: "support-ip", subject: ip, limit: 5 },
    { bucket: "support-email", subject: email, limit: 3 },
  ]);

  if (allowed === "refused") {
    // Nothing recorded and nothing sent. Deliberately not a distinguishable message: a caller
    // learning which bucket stopped them learns whether that address has written in before.
    return NextResponse.json(
      { error: "Too many messages from here just now. Please try again shortly." },
      { status: 429 },
    );
  }

  // Recorded before the email, and never allowed to stop it.
  //
  // The email is what actually notifies anybody; the row is what makes a queue possible, so a
  // visitor's request still reaches somebody even if this fails. It runs with the anon key like
  // every other query from this app — `submit_support_request` is security definer and resolves
  // attribution itself, so a visitor with no session gets a row with a null profile and the
  // address they typed, which the console matches to an account at read time.
  try {
    const { error } = await supabase.rpc("submit_support_request", {
      p_category: category,
      p_message: message,
      p_email: email,
      p_name: nullableArg(name || null),
      p_source: "web",
    });
    if (error) console.error("[support] could not record the request:", error.message);
  } catch (err) {
    console.error("[support] could not record the request:", (err as Error).message);
  }

  try {
    // `sendReceipt` is what makes this an amplifier: the internal alert goes to our own address
    // and is harmless, while the receipt goes wherever the caller said. When the limiter could
    // not be consulted at all we still want a visitor's message to reach support, so the alert is
    // sent and the receipt is not — the degraded mode drops the convenience, never the report,
    // and never leaves the relay open.
    await sendSupportEmails({ name, email, category, message, sendReceipt: allowed === "allowed" });
  } catch (err) {
    console.error("[support] Zoho SMTP send failed:", (err as Error).message);
    return NextResponse.json({ error: "Something went wrong. Please try again." }, { status: 502 });
  }

  return NextResponse.json({ ok: true });
}

/** Not a real ticketing system (see the "what are my free options" conversation) - just a
 * short reference so a reply-thread subject line stays stable and the two emails below
 * visibly refer to the same submission. */
function generateTicketId(): string {
  return Math.random().toString(36).slice(2, 8).toUpperCase();
}

function formatDateTime(date: Date): string {
  return new Intl.DateTimeFormat("en-AU", { dateStyle: "medium", timeStyle: "short" }).format(date);
}

/** Sync/tracking issues get the two concrete troubleshooting steps; everything else (Feature
 * Request, Feedback, etc.) gets a generic pointer instead - those tips would look wrong under
 * a category they don't apply to. */
function waitTipsHtml(category: string): string {
  if (category === "Bug Report" || category === "Flight Tracking") {
    return `
      <div style="font-family:Georgia,'Times New Roman',serif;font-size:19px;line-height:26px;mso-line-height-rule:exactly;color:#1c2a38;padding-bottom:12px;">While you wait</div>
      <div style="font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:26px;mso-line-height-rule:exactly;color:#5b6b7a;padding-bottom:12px;">Two things that fix most sync and tracking issues:</div>
      <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="width:100%;">
        <tr>
          <td width="26" valign="top" style="width:26px;font-family:Georgia,'Times New Roman',serif;font-size:16px;color:#6fbf8b;mso-line-height-rule:exactly;line-height:26px;">1.</td>
          <td valign="top" style="font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:26px;mso-line-height-rule:exactly;color:#5b6b7a;padding-bottom:8px;">Check you're both on the latest version of the app.</td>
        </tr>
        <tr>
          <td width="26" valign="top" style="width:26px;font-family:Georgia,'Times New Roman',serif;font-size:16px;color:#6fbf8b;mso-line-height-rule:exactly;line-height:26px;">2.</td>
          <td valign="top" style="font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:26px;mso-line-height-rule:exactly;color:#5b6b7a;">Turn background app refresh back on for Twofold in iOS Settings - it can switch off after a big update.</td>
        </tr>
      </table>`;
  }
  return `<div style="font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:26px;mso-line-height-rule:exactly;color:#5b6b7a;">In the meantime, our <a href="${SITE_URL}/faq" style="color:#3d8fc9;">FAQ</a> covers most common questions.</div>`;
}

async function sendSupportEmails(input: {
  name: string;
  email: string;
  category: string;
  message: string;
  /// The receipt to the address the caller typed. The only one of the two that can be aimed at
  /// somebody else, so it is the only one with a switch.
  sendReceipt: boolean;
}): Promise<void> {
  const { transport, from } = createZohoTransport();
  const firstName = input.name.split(/\s+/)[0] || "there";
  const ticketId = generateTicketId();
  const receivedAt = formatDateTime(new Date());
  const escapedMessage = escapeHtml(input.message).replace(/\n/g, "<br>");

  const internalHtml = renderTemplate("support-internal-alert", {
    subject: `[${input.category}] Website support request - #${ticketId}`,
    // Escaped like every other token on this call. `renderTemplate` substitutes verbatim and
    // requires callers to pre-escape; this one was missed, and it lands in markup.
    preheader: escapeHtml(`${input.name || "Someone"} · ${input.category} · ${input.message.slice(0, 90)}`),
    ticket_category: escapeHtml(input.category),
    ticket_id: ticketId,
    ticket_subject: escapeHtml(`${input.category} - website support request`),
    user_name: escapeHtml(input.name || "(no name given)"),
    user_email: escapeHtml(input.email),
    received_at: receivedAt,
    message_body: escapedMessage,
    first_name: escapeHtml(firstName),
  });

  const receivedHtml = renderTemplate("support-received", {
    subject: `We got your message - #${ticketId}`,
    preheader: "Thanks for writing in - here's a copy of what you sent us.",
    first_name: escapeHtml(firstName),
    response_time: "1-2 business days",
    ticket_id: ticketId,
    received_at: receivedAt,
    message_body: escapedMessage,
    wait_tips_html: waitTipsHtml(input.category),
    help_center_url: `${SITE_URL}/faq`,
    support_email: SUPPORT_EMAIL,
  });

  try {
    await transport.sendMail({
      from,
      to: SUPPORT_EMAIL,
      // Replying in the inbox goes straight back to the visitor, same as the app's own flow.
      replyTo: input.email,
      subject: extractSubject(internalHtml),
      html: internalHtml,
      text: `Category: ${input.category}\nFrom: ${input.name || "(no name given)"} - ${input.email}\n\n${input.message}`,
    });
    if (input.sendReceipt) {
      await transport.sendMail({
        from,
        to: input.email,
        replyTo: SUPPORT_EMAIL,
        subject: extractSubject(receivedHtml),
        html: receivedHtml,
      });
    }
  } finally {
    transport.close();
  }
}
