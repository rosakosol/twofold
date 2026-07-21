import { NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/db/types";

// Port of the old site/functions/api/waitlist.ts (Cloudflare Pages Function + D1) —
// same validation/honeypot logic, writing to Supabase's waitlist_signups table instead
// of D1 (which Vercel can't reach), same two Resend emails via raw fetch (no SDK
// change needed, Resend's HTTP API works the same from any server runtime).

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
  const apiKey = process.env.RESEND_API_KEY;
  const fromEmail = process.env.WAITLIST_FROM_EMAIL ?? "Twofold <hello@twofoldapp.com.au>";
  const notifyEmail = process.env.WAITLIST_NOTIFY_EMAIL ?? "hello@twofoldapp.com.au";
  if (!apiKey) {
    console.warn("[waitlist] RESEND_API_KEY not set — skipping confirmation emails");
    return;
  }

  const send = (payload: Record<string, unknown>) =>
    fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });

  const results = await Promise.allSettled([
    send({
      from: fromEmail,
      to: email,
      subject: "You're on the Twofold Android waitlist",
      html: "<p>Thanks for your interest in Twofold!</p><p>We're building the Android version next — we'll email this address the moment it's ready to download.</p><p>— The Twofold team</p>",
    }),
    send({
      from: fromEmail,
      to: notifyEmail,
      subject: "New Twofold Android waitlist signup",
      html: `<p>New signup: ${escapeHtml(email)}</p>`,
    }),
  ]);
  for (const result of results) {
    if (result.status === "rejected") console.error("[waitlist] email send failed:", result.reason);
  }
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (char) => {
    switch (char) {
      case "&":
        return "&amp;";
      case "<":
        return "&lt;";
      case ">":
        return "&gt;";
      case '"':
        return "&quot;";
      default:
        return "&#39;";
    }
  });
}
