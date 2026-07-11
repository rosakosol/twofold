interface Env {
  DB: D1Database;
  RESEND_API_KEY: string;
  FROM_EMAIL: string;
  NOTIFY_EMAIL: string;
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export const onRequestPost: PagesFunction<Env> = async (context) => {
  const { request, env } = context;

  let body: { email?: string; company?: string };
  try {
    body = await request.json();
  } catch {
    return json({ error: "Invalid request." }, 400);
  }

  // Honeypot: bots tend to fill every field. Pretend success so we don't tip them off.
  if (body.company) {
    return json({ ok: true }, 200);
  }

  const email = (body.email ?? "").trim().toLowerCase();
  if (!email || !EMAIL_RE.test(email) || email.length > 320) {
    return json({ error: "Enter a valid email address." }, 400);
  }

  try {
    await context.env.DB.prepare(
      "INSERT INTO waitlist_signups (email, created_at) VALUES (?, ?)"
    )
      .bind(email, new Date().toISOString())
      .run();
  } catch (err: any) {
    if (String(err?.message ?? "").includes("UNIQUE")) {
      return json({ error: "You're already on the list." }, 409);
    }
    return json({ error: "Something went wrong. Please try again." }, 500);
  }

  context.waitUntil(sendEmails(env, email));

  return json({ ok: true }, 200);
};

function json(data: unknown, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function sendEmails(env: Env, email: string): Promise<void> {
  const send = (payload: Record<string, unknown>) =>
    fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });

  await Promise.allSettled([
    send({
      from: env.FROM_EMAIL,
      to: email,
      subject: "You're on the Twofold Android waitlist",
      html: `<p>Thanks for your interest in Twofold!</p><p>We're building the Android version next — we'll email this address the moment it's ready to download.</p><p>— The Twofold team</p>`,
    }),
    send({
      from: env.FROM_EMAIL,
      to: env.NOTIFY_EMAIL,
      subject: "New Twofold Android waitlist signup",
      html: `<p>New signup: ${escapeHtml(email)}</p>`,
    }),
  ]);
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
