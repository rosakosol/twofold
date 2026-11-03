import { NextResponse } from "next/server";
import { createZohoTransport } from "@/lib/mail/zoho";
import { renderTemplate, extractSubject } from "@/lib/mail/renderTemplate";
import { escapeHtml } from "@/lib/mail/escapeHtml";
import { SUPPORT_EMAIL, SITE_URL } from "@/lib/mail/companyInfo";
import { createServiceClient } from "@/lib/supabase/service";
import { nullableArg } from "@/lib/db/nullableArg";
import { validateSupportRequest } from "@/lib/validation/support";
import { emailTimestamp } from "@/lib/console/format";

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

  // The same rules the form checks before sending (lib/validation/support.ts). `field` lets the
  // form mark the input at fault.
  const validation = validateSupportRequest(body);
  if (!validation.ok) {
    return NextResponse.json({ error: validation.error, field: validation.field }, { status: 400 });
  }
  const { name, email, category, message } = validation.value;

  // Two buckets, because they fail differently. The email is trivially rotated — an attacker
  // picks a new recipient for each send, which is the whole point of a relay — so it is the IP
  // that has to carry the limit. The email bucket is the narrower one, and stops the same address
  // being mailed repeatedly from a rotating source.
  //
  // Service role for both the limiter and the request row: neither function is callable with the
  // public key any more, so a script can no longer flood the queue or fill someone else's buckets
  // without going through this route (see lib/supabase/service.ts).
  const supabase = createServiceClient();
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
  // visitor's request still reaches somebody even if this fails. It runs as the service role, with
  // no user, so `submit_support_request` records a null profile and the address typed, which the
  // console matches to an account at read time.
  let recorded = false;
  try {
    const { error } = await supabase.rpc("submit_support_request", {
      p_category: category,
      p_message: message,
      p_email: email,
      p_name: nullableArg(name || null),
      p_source: "web",
    });
    if (error) console.error("[support] could not record the request:", error.message);
    else recorded = true;
  } catch (err) {
    console.error("[support] could not record the request:", (err as Error).message);
  }

  // `sendReceipt` is what makes this an amplifier: the internal alert goes to our own address
  // and is harmless, while the receipt goes wherever the caller said. When the limiter could
  // not be consulted at all we still want a visitor's message to reach support, so the alert is
  // sent and the receipt is not — the degraded mode drops the convenience, never the report,
  // and never leaves the relay open.
  const { alerted } = await sendSupportEmails({
    name,
    email,
    category,
    message,
    sendReceipt: allowed === "allowed",
    recorded,
  });

  // Success means support has it: the row is in the console's queue, or the alert is in the
  // inbox. Only when neither happened is "try again" the right answer. This used to return 502
  // whenever any email failed, the visitor's own receipt included, after the row was stored and
  // the alert sent, so a retry filed the same request twice and spent the address's rate limit.
  if (!recorded && !alerted) {
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

/** With its zone named: the receipt shows this to the visitor as "received at". */
function formatDateTime(date: Date): string {
  return emailTimestamp(date);
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
  /// Whether the request row was stored. A receipt is a promise that support has the message, so
  /// it goes only once the row or the alert landed.
  recorded: boolean;
}): Promise<{ alerted: boolean }> {
  // Never throws: the caller decides what a failure means from what did get through. Errors are
  // logged by message only, which never includes the visitor's address.
  let mailer: ReturnType<typeof createZohoTransport>;
  try {
    mailer = createZohoTransport();
  } catch (err) {
    console.error("[support] mail is not configured:", (err as Error).message);
    return { alerted: false };
  }
  const { transport, from } = mailer;
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

  let alerted = false;
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
    alerted = true;
  } catch (err) {
    console.error("[support] internal alert failed:", (err as Error).message);
  }

  if (input.sendReceipt && (alerted || input.recorded)) {
    try {
      await transport.sendMail({
        from,
        to: input.email,
        replyTo: SUPPORT_EMAIL,
        subject: extractSubject(receivedHtml),
        html: receivedHtml,
      });
    } catch (err) {
      // The visitor misses their copy; support still has the request.
      console.error("[support] receipt failed:", (err as Error).message);
    }
  }

  transport.close();
  return { alerted };
}
