import { NextResponse } from "next/server";
import { createZohoTransport } from "@/lib/mail/zoho";

// Web counterpart to the iOS app's submit-help-message edge function
// (supabase/functions/submit-help-message) — same category list and same recipient
// (support@twofoldapp.com.au), sent via the same Zoho Mail SMTP account (see
// lib/mail/zoho.ts for the transport + required env vars). This one has to work for an
// anonymous site visitor with no Supabase session, so it can't reuse that function's
// Bearer-token-gated auth.

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const RECIPIENT = "support@twofoldapp.com.au";

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

  try {
    await sendSupportEmail({ name, email, category, message });
  } catch (err) {
    console.error("[support] Zoho SMTP send failed:", (err as Error).message);
    return NextResponse.json({ error: "Something went wrong. Please try again." }, { status: 502 });
  }

  return NextResponse.json({ ok: true });
}

async function sendSupportEmail(input: { name: string; email: string; category: string; message: string }): Promise<void> {
  const { transport, from } = createZohoTransport();

  const bodyLines = [
    `Category: ${input.category}`,
    `From: ${input.name || "(no name given)"} — ${input.email}`,
    "",
    input.message,
  ];

  try {
    await transport.sendMail({
      from,
      to: RECIPIENT,
      // Replying in the inbox goes straight back to the visitor, same as the app's own flow.
      replyTo: input.email,
      subject: `[${input.category}] Website support request${input.name ? ` from ${input.name}` : ""}`,
      text: bodyLines.join("\n"),
    });
  } finally {
    transport.close();
  }
}
