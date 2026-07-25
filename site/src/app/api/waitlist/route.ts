import { NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/db/types";
import { createZohoTransport } from "@/lib/mail/zoho";
import { renderTemplate, extractSubject } from "@/lib/mail/renderTemplate";
import { escapeHtml } from "@/lib/mail/escapeHtml";
import { SUPPORT_EMAIL, SITE_URL } from "@/lib/mail/companyInfo";

// Port of the old site/functions/api/waitlist.ts (Cloudflare Pages Function + D1) —
// same validation/honeypot logic, writing to Supabase's waitlist_signups table instead
// of D1 (which Vercel can't reach). Emails now go via the same Zoho Mail SMTP account
// /api/support uses (see lib/mail/zoho.ts) rather than Resend, which this project isn't
// using — was a raw-fetch call to Resend's HTTP API before this migration.
//
// Uses lib/mail/templates/waitlist-confirmation.html (to the signer) and
// waitlist-internal-alert.html (to WAITLIST_NOTIFY_EMAIL) — see that folder's README.md.
// Both were trimmed down from their original design: no referral/invite system, no
// device/location/survey tracking, no admin dashboard, and no waitlist-position/signup-count
// stats — none of that is tracked (or worth tracking) today, so those sections were dropped
// rather than filled with fabricated values.

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// No cookies/user session involved (anonymous, unauthenticated form) — a plain
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

  const { error } = await supabase.from("waitlist_signups").insert({ email });
  if (error) {
    // 23505 = Postgres unique_violation (the "already on the list" case).
    if (error.code === "23505") {
      return NextResponse.json({ error: "You're already on the list." }, { status: 409 });
    }
    return NextResponse.json({ error: "Something went wrong. Please try again." }, { status: 500 });
  }

  await sendEmails(email);

  return NextResponse.json({ ok: true });
}

async function sendEmails(email: string): Promise<void> {
  const notifyEmail = process.env.WAITLIST_NOTIFY_EMAIL ?? "hello@twofoldapp.com.au";

  let mailer: ReturnType<typeof createZohoTransport>;
  try {
    mailer = createZohoTransport();
  } catch (err) {
    // Best-effort, same as before: the signup itself already succeeded (the insert above),
    // so a missing/misconfigured mail setup shouldn't fail the request — just log it.
    console.warn("[waitlist] Zoho SMTP not configured — skipping confirmation emails:", (err as Error).message);
    return;
  }
  const { transport, from } = mailer;

  try {
    const confirmationHtml = renderTemplate("waitlist-confirmation", {
      subject: "You're on the Twofold Android waitlist",
      preheader: "Thanks for signing up — we'll email this address the moment Android is ready.",
      support_email: SUPPORT_EMAIL,
      site_url: SITE_URL,
    });

    const alertHtml = renderTemplate("waitlist-internal-alert", {
      subject: "New Twofold Android waitlist signup",
      preheader: `New signup: ${email}`,
      signup_at: new Intl.DateTimeFormat("en-AU", { dateStyle: "medium", timeStyle: "short" }).format(new Date()),
      user_email: escapeHtml(email),
    });

    const results = await Promise.allSettled([
      transport.sendMail({
        from,
        to: email,
        subject: extractSubject(confirmationHtml),
        html: confirmationHtml,
      }),
      transport.sendMail({
        from,
        to: notifyEmail,
        subject: extractSubject(alertHtml),
        html: alertHtml,
      }),
    ]);
    for (const result of results) {
      if (result.status === "rejected") console.error("[waitlist] email send failed:", result.reason);
    }
  } finally {
    transport.close();
  }
}
