import { NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/db/types";
import { createZohoTransport } from "@/lib/mail/zoho";
import { renderTemplate, extractSubject } from "@/lib/mail/renderTemplate";
import { escapeHtml } from "@/lib/mail/escapeHtml";
import { listUnsubscribeHeaders, unsubscribeUrl } from "@/lib/mail/unsubscribe";

// Port of the old site/functions/api/waitlist.ts (Cloudflare Pages Function + D1) -
// same validation/honeypot logic, writing to Supabase's waitlist_signups table instead
// of D1 (which Vercel can't reach). Emails go via the same Zoho Mail SMTP account
// /api/support uses - see lib/mail/zoho.ts, which is the only mail transport this
// project has.
//
// Uses lib/mail/templates/android-waitlist.html (to the signer) and
// waitlist-internal-alert.html (to WAITLIST_NOTIFY_EMAIL) - see that folder's README.md.
// Both were trimmed down from their original design: no referral/invite system, no
// device/location/survey tracking, no admin dashboard, and no waitlist-position/signup-count
// stats - none of that is tracked (or worth tracking) today, so those sections were dropped
// rather than filled with fabricated values.

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// No cookies/user session involved (anonymous, unauthenticated form) - a plain
// anon-key client is simpler and more correct here than the cookie-based SSR client
// used elsewhere in this app for signed-in requests.
const supabase = createClient<Database>(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);

export async function POST(request: Request) {
  let body: { email?: string; company?: string };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid request." }, { status: 400 });
  }

  // Honeypot: bots tend to fill every field. Pretend success so we don't tip them off.
  if (body.company) {
    return NextResponse.json({ ok: true });
  }

  const email = (body.email ?? "").trim().toLowerCase();
  if (!email || !EMAIL_RE.test(email) || email.length > 320) {
    return NextResponse.json({ error: "Enter a valid email address." }, { status: 400 });
  }

  // The same limiter the support form uses: this sends mail to an address a visitor typed, so
  // without it the form is a way to send our email to anybody (see 20261110000500). Per caller
  // and per address. A limiter outage lets the signup through rather than losing it.
  for (const [bucket, subject, limit] of [
    ["waitlist-ip", callerIP(request), 5],
    ["waitlist-email", email, 2],
  ] as const) {
    const { data: allowed, error: limitError } = await supabase.rpc("consume_anon_rate_limit", {
      p_bucket: bucket,
      p_subject: subject,
      p_limit: limit,
      p_window: "01:00:00",
    });
    if (limitError) {
      console.error(`[waitlist] rate limit unavailable (${bucket}):`, limitError.message);
      break;
    }
    if (allowed === false) {
      return NextResponse.json({ error: "Too many attempts. Please try again in an hour." }, { status: 429 });
    }
  }

  // Joins, and hands back the token the confirmation's "Leave the waitlist" link carries
  // (20261112000000). "exists" is the already-on-the-list case.
  const { data, error } = await supabase.rpc("join_android_waitlist", { p_email: email });
  const result = Array.isArray(data) ? data[0] : null;
  if (error || !result) {
    return NextResponse.json({ error: "Something went wrong. Please try again." }, { status: 500 });
  }
  if (result.status === "exists") {
    return NextResponse.json({ error: "You're already on the list." }, { status: 409 });
  }

  await sendEmails(email, result.token);

  return NextResponse.json({ ok: true });
}

function callerIP(request: Request): string {
  const forwarded = request.headers.get("x-forwarded-for");
  if (forwarded) return forwarded.split(",")[0]!.trim();
  return request.headers.get("x-real-ip")?.trim() || "unknown";
}

async function sendEmails(email: string, token: string): Promise<void> {
  const notifyEmail = process.env.WAITLIST_NOTIFY_EMAIL ?? "support@twofoldapp.com.au";

  let mailer: ReturnType<typeof createZohoTransport>;
  try {
    mailer = createZohoTransport();
  } catch (err) {
    // Best-effort, same as before: the signup itself already succeeded (the insert above),
    // so a missing/misconfigured mail setup shouldn't fail the request - just log it.
    console.warn("[waitlist] Zoho SMTP not configured - skipping confirmation emails:", (err as Error).message);
    return;
  }
  const { transport, from, sender } = mailer;

  try {
    const confirmationHtml = renderTemplate("android-waitlist", {
      Email: escapeHtml(email),
      UnsubscribeURL: escapeHtml(unsubscribeUrl(token, "android_waitlist")),
    });

    const alertHtml = renderTemplate("waitlist-internal-alert", {
      subject: "New Twofold Android waitlist signup",
      preheader: `New signup: ${email}`,
      signup_at: new Intl.DateTimeFormat("en-AU", { dateStyle: "medium", timeStyle: "short" }).format(new Date()),
      user_email: escapeHtml(email),
    });

    const results = await Promise.allSettled([
      // An announcement rather than a receipt: nobody filed a ticket, they signed up to hear from
      // us, so this is the one piece of mail the site sends where support@ as the From reads
      // wrong. `sender` supplies Reply-To: support@ with it, so a reply still reaches the queue.
      transport.sendMail({
        ...sender("announcement"),
        to: email,
        subject: extractSubject(confirmationHtml).replace(/&#8217;/g, "\u2019"),
        html: confirmationHtml,
        headers: listUnsubscribeHeaders(token, "android_waitlist"),
      }),
      // Internal, to us. Stays transactional - there is nobody outside to read the From.
      transport.sendMail({
        from,
        to: notifyEmail,
        subject: extractSubject(alertHtml),
        html: alertHtml,
      }),
    ]);
    for (const result of results) {
      // The reason, not the rejection object: a nodemailer failure carries the envelope, so
      // logging it whole wrote the signup's email address into Vercel's logs.
      if (result.status === "rejected") {
        console.error("[waitlist] email send failed:", (result.reason as Error)?.message ?? "unknown");
      }
    }
  } finally {
    transport.close();
  }
}
