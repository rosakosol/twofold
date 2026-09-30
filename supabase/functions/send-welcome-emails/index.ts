// Welcome email, sent once per account shortly after sign-up. Cron-triggered only
// (supabase/migrations/20261101000000_welcome_email.sql).
//
// WHY THIS EXISTS, WHICH IS NOT MARKETING
//
// Email confirmation is off, and deliberately: `signUp` returning a session is what lets
// SaveAccountView flush an entire onboarding in one shot, what lets an invite code be generated,
// and what lets a web purchase follow a sign-up. The cost is the one failure confirmation would
// have caught — a mistyped address makes an unrecoverable account, because password recovery goes
// somewhere its owner cannot read. This email cannot prevent that, but it reaches the one person
// who can act on it: whoever really owns the address that was typed. That is why the "didn't sign
// up?" line is not boilerplate at the bottom; it is the point.
//
// Requires the service-role key as a bearer token, the same explicit check
// send-partner-invite-reminders and refresh-due-flights already make. Without it any authenticated
// user could invoke this and make us mail every unstamped profile on demand.
//
// IDEMPOTENCY
//
// A row is claimed by stamping `welcome_email_sent_at` *before* the send, not after. Sending twice
// is worse than not sending: the second copy lands on someone who may not have asked for the
// first, and to an address we already suspect might be wrong. A crash between the stamp and the
// send therefore loses one welcome email, which is the right way round.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { closeQuietly, dotStuff, fromAddress, singleLine, smtpClient } from "../_shared/mail.ts";

/// How far back a run will look. Belt to the migration's braces: that backfill stamps every
/// profile that existed when it ran, so the first run has nothing old to find — but a restore, a
/// re-run against another environment, or a paused cron could all present a pile of ancient
/// unstamped rows, and none of those are a reason to mail a year of sign-ups at once.
const MAX_AGE_HOURS = 48;

/// Per run. A backlog drains over subsequent runs rather than in one SMTP session; Zoho rate-limits
/// and a run that trips it fails all of them rather than the tail.
const BATCH = 50;

const SUPPORT_EMAIL = "support@twofoldapp.com.au";

function subject(): string {
  return "Welcome to Twofold";
}

function textBody(firstName: string): string {
  const greeting = firstName ? `Hi ${firstName},` : "Hi,";
  return dotStuff(
    [
      greeting,
      "",
      "Your Twofold account is ready. Twofold is for couples doing distance - track each",
      "other's flights, save memories to the places they happened, and watch the miles you've",
      "travelled for each other add up.",
      "",
      "If you haven't already, invite your partner from the app - almost everything in Twofold",
      "is built for two.",
      "",
      "---",
      "",
      "Didn't sign up for this?",
      "",
      "Someone may have mistyped their own email address and reached yours instead. If that's",
      `what happened, reply to this note or write to ${SUPPORT_EMAIL} and we'll remove the`,
      "account. Nobody can read your email or act as you - the address was only typed in, never",
      "confirmed - but we'd rather take it off your hands than leave it sitting there.",
      "",
      "- Twofold",
    ].join("\n"),
  );
}

function htmlBody(firstName: string): string {
  const greeting = firstName ? `Hi ${escapeHtml(firstName)},` : "Hi,";
  return `<!DOCTYPE html>
<html><body style="margin:0;padding:24px;background:#e4f4e6;font-family:Arial,Helvetica,sans-serif;color:#1c2a38;">
  <div style="max-width:520px;margin:0 auto;background:#ffffff;border-radius:20px;padding:32px;">
    <h1 style="margin:0 0 16px;font-size:22px;color:#1c2a38;">Welcome to Twofold</h1>
    <p style="margin:0 0 16px;font-size:15px;line-height:22px;">${greeting}</p>
    <p style="margin:0 0 16px;font-size:15px;line-height:22px;">
      Your Twofold account is ready. Twofold is for couples doing distance &mdash; track each
      other's flights, save memories to the places they happened, and watch the miles you've
      travelled for each other add up.
    </p>
    <p style="margin:0 0 24px;font-size:15px;line-height:22px;">
      If you haven't already, invite your partner from the app &mdash; almost everything in
      Twofold is built for two.
    </p>
    <hr style="border:0;border-top:1px solid rgba(28,42,56,0.09);margin:0 0 24px;">
    <p style="margin:0 0 8px;font-size:15px;font-weight:bold;">Didn't sign up for this?</p>
    <p style="margin:0;font-size:14px;line-height:21px;color:#5b6b7a;">
      Someone may have mistyped their own email address and reached yours instead. If that's what
      happened, reply to this note or write to
      <a href="mailto:${SUPPORT_EMAIL}" style="color:#d1465a;font-weight:bold;text-decoration:none;">${SUPPORT_EMAIL}</a>
      and we'll remove the account. Nobody can read your email or act as you &mdash; the address was
      only typed in, never confirmed &mdash; but we'd rather take it off your hands than leave it
      sitting there.
    </p>
  </div>
</body></html>`;
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

Deno.serve(async (req) => {
  const expected = `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`;
  if (req.headers.get("Authorization") !== expected) {
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  }

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const cutoff = new Date(Date.now() - MAX_AGE_HOURS * 3600 * 1000).toISOString();

  const { data: pending, error: pendingErr } = await serviceClient
    .from("profiles")
    .select("id, first_name, created_at")
    .is("welcome_email_sent_at", null)
    .gte("created_at", cutoff)
    .order("created_at", { ascending: true })
    .limit(BATCH);

  if (pendingErr) {
    console.error("[welcome] could not read pending profiles", pendingErr.message);
    return Response.json({ error: "query failed" }, { status: 500 });
  }
  if (!pending?.length) {
    return Response.json({ sent: 0, skipped: 0 });
  }

  let client: ReturnType<typeof smtpClient> | undefined;
  let sent = 0;
  let skipped = 0;

  try {
    client = smtpClient();

    for (const profile of pending) {
      // The address lives in auth.users, not profiles — this is the only place that needs it, and
      // copying it into profiles would mean a second copy to keep in step with account changes.
      const { data: userResult, error: userErr } = await serviceClient.auth.admin.getUserById(
        profile.id,
      );
      const email = userResult?.user?.email;

      if (userErr || !email) {
        // An Apple relay address is a real address and gets mail like any other. No email at all
        // means an account that cannot be written to, so stamp it and move on rather than
        // retrying it every fifteen minutes forever.
        await serviceClient
          .from("profiles")
          .update({ welcome_email_sent_at: new Date().toISOString() })
          .eq("id", profile.id);
        skipped++;
        continue;
      }

      // Claimed before the send. See the note at the top of the file on why this order.
      const { error: claimErr } = await serviceClient
        .from("profiles")
        .update({ welcome_email_sent_at: new Date().toISOString() })
        .eq("id", profile.id)
        .is("welcome_email_sent_at", null);

      if (claimErr) {
        console.error("[welcome] could not claim", profile.id, claimErr.message);
        continue;
      }

      const firstName = singleLine(profile.first_name ?? "");

      try {
        await client.send({
          from: fromAddress(),
          to: email,
          // The body invites a reply from someone telling us the address is not theirs, so the
          // reply has to reach a human. submit-help-message sets this for the same reason.
          replyTo: SUPPORT_EMAIL,
          subject: subject(),
          content: textBody(firstName),
          html: htmlBody(firstName),
        });
        sent++;
      } catch (err) {
        // Already claimed, so this one is lost rather than retried — deliberately. Logged with the
        // profile id so a pattern (one bad mailbox, or Zoho refusing everything) is visible.
        console.error("[welcome] send failed", profile.id, err instanceof Error ? err.message : err);
      }
    }
  } catch (err) {
    console.error("[welcome] fatal", err instanceof Error ? err.message : err);
    return Response.json({ error: "send failed", sent, skipped }, { status: 500 });
  } finally {
    await closeQuietly(client);
  }

  return Response.json({ sent, skipped });
});
