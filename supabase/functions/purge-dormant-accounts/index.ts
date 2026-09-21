// Warns, and then closes, accounts nobody has opened in two years.
//
// Cron-triggered only, once a day — see 20261029000200_dormant_accounts_cron.sql. The policy
// itself (how long, which warning windows, whose activity counts) lives in the database, in
// `public.dormancy_cohort`; this function only carries out what that returns. See
// 20261029000100_dormant_accounts.sql for why the timer reads activity rather than subscription
// state, and why one partner opening the app keeps both accounts alive.
//
// Requires the service-role key as a bearer token, the same explicit check `send-streak-reminders`
// and `refresh-due-flights` use. Without it, any authenticated user could invoke the thing that
// deletes accounts.
//
// ---------------------------------------------------------------------------
// The cap
// ---------------------------------------------------------------------------
//
// At most `MAX_CLOSURES_PER_RUN` accounts are closed in one pass, and the run reports when it hits
// that. This is not a performance guard — it is the blast radius of a bug. If a clock skewed, a
// backfill went wrong, or someone fat-fingered the interval in a migration, the difference between
// "a hundred accounts closed and an alarming log line" and "every account in the app closed
// overnight" is this constant. Closures are idempotent and the cohort is stable, so a legitimately
// large backlog simply drains over several nights.
//
// ---------------------------------------------------------------------------
// Warn first, always
// ---------------------------------------------------------------------------
//
// Email is the channel that matters here. The people being warned are by definition not opening
// the app, so a push notification is a courtesy to whoever still has it installed rather than the
// thing being relied on — and a push failure never blocks the email. A *warning* that fails to
// send does block its stamp, though: `mark_dormancy_warned` is only called for the accounts whose
// mail actually went out, so a Zoho outage means those accounts are warned tomorrow instead of
// being silently marked as told.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { sendAPNs } from "../_shared/apns.ts";
import { closeQuietly, fromAddress, singleLine, smtpClient } from "../_shared/mail.ts";

const MAX_CLOSURES_PER_RUN = 200;

interface CohortRow {
  profile_id: string;
  email: string;
  first_name: string | null;
  couple_id: string | null;
  stage: "warn_30" | "warn_7" | "delete";
  cohort_last_active_at: string;
  delete_after: string;
}

function greeting(firstName: string | null): string {
  const name = firstName ? singleLine(firstName) : "";
  // "Deleted User" is what a scrubbed profile is called; addressing somebody by it would be
  // both absurd and a small privacy tell about how the table works.
  return name && name !== "Deleted User" ? `Hi ${name},` : "Hi,";
}

function warningEmail(row: CohortRow): { subject: string; body: string } {
  const days = row.stage === "warn_7" ? 7 : 30;
  const when = new Date(row.delete_after).toLocaleDateString("en-AU", {
    day: "numeric",
    month: "long",
    year: "numeric",
  });

  const subject = days === 7
    ? "Your Twofold account closes in 7 days"
    : "Your Twofold account closes in 30 days";

  const body = [
    greeting(row.first_name),
    "",
    `Nobody has opened your Twofold account in nearly two years, so it's scheduled to close on ${when}.`,
    "",
    "Opening the app is all it takes to stop that — signing in resets the clock and you'll keep everything.",
    "",
    "If you'd rather let it go, you don't need to do anything. When the date passes, the account closes and the trips, memories, photos and answers you shared are deleted 90 days later. If you're part of a couple, either of you opening the app keeps it all for both of you.",
    "",
    "Want a copy first? Sign in and use Settings → Export your data before the date above.",
    "",
    "— Twofold",
  ].join("\n");

  return { subject, body };
}

Deno.serve(async (req) => {
  const expected = `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`;
  if (req.headers.get("Authorization") !== expected) {
    return Response.json({ error: "Forbidden" }, { status: 403 });
  }
  if (req.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405 });
  }

  // `dryRun` lists what would happen and changes nothing. The first production run of an
  // irreversible job should be one of these.
  //
  // `asOf` moves the clock the cohort is measured against, and only a dry run may pass it. The
  // dormancy period is 24 months, so on a young account base every honest run of this reports zero
  // and will keep doing so for about two years — a working cohort and a broken one are
  // indistinguishable until the day it finally matters. `asOf` asks the real data a hypothetical
  // question instead: what would this do in December 2028? The pgTAP suite already stands two years
  // forward the same way; this is the same idea against production rows.
  let dryRun = false;
  let asOf: string | null = null;
  try {
    const body = await req.json();
    dryRun = body?.dryRun === true;
    if (typeof body?.asOf === "string") asOf = body.asOf;
  } catch {
    // No body is the normal cron case.
  }

  if (asOf !== null) {
    // Guarded hard rather than politely. Honouring a future `asOf` on a real run would close every
    // account that will *ever* be due, years early and irreversibly — the single worst thing this
    // function could be made to do, and one query parameter away.
    if (!dryRun) {
      return Response.json(
        { error: "'asOf' is only allowed with dryRun, because it would close accounts early" },
        { status: 400 },
      );
    }
    if (Number.isNaN(Date.parse(asOf))) {
      return Response.json({ error: "'asOf' must be a date this runtime can parse" }, { status: 400 });
    }
  }

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  const { data: cohort, error: cohortErr } = await serviceClient.rpc(
    "dormancy_cohort",
    asOf ? { p_now: new Date(asOf).toISOString() } : {},
  );
  if (cohortErr) {
    console.error("dormancy_cohort failed", cohortErr);
    return Response.json({ error: "Could not read the dormancy cohort" }, { status: 500 });
  }

  const rows = (cohort ?? []) as CohortRow[];
  const toWarn = rows.filter((r) => r.stage === "warn_30" || r.stage === "warn_7");
  const toClose = rows.filter((r) => r.stage === "delete");
  const capped = toClose.length > MAX_CLOSURES_PER_RUN;
  const closing = capped ? toClose.slice(0, MAX_CLOSURES_PER_RUN) : toClose;

  if (capped) {
    console.error(
      `dormancy: ${toClose.length} accounts are due for closure, which is over the ${MAX_CLOSURES_PER_RUN} cap. ` +
        `Closing ${MAX_CLOSURES_PER_RUN} and leaving the rest for the next run — if this is not a genuine backlog, ` +
        `something is wrong with the timer and it should be investigated before tomorrow's run.`,
    );
  }

  if (dryRun) {
    return Response.json({
      dryRun: true,
      // Echoed back so a report cannot be mistaken for one about today, which is the whole risk of
      // being able to ask about a date years away.
      asOf: asOf ?? "now",
      warn30: toWarn.filter((r) => r.stage === "warn_30").length,
      warn7: toWarn.filter((r) => r.stage === "warn_7").length,
      wouldClose: toClose.length,
      cappedAt: capped ? MAX_CLOSURES_PER_RUN : null,
    });
  }

  // ---------------------------------------------------------------------------
  // Warnings
  // ---------------------------------------------------------------------------
  const warned: string[] = [];
  let warnFailures = 0;

  if (toWarn.length > 0) {
    let client;
    try {
      client = smtpClient();
    } catch (err) {
      // No mailbox means no warnings can go out. Closures still run: those accounts were warned
      // in earlier passes, and holding them back would only delay a deletion that is already due.
      console.error("dormancy: SMTP is not configured, skipping all warnings this run", err);
      client = null;
    }

    if (client) {
      for (const row of toWarn) {
        const { subject, body } = warningEmail(row);
        try {
          await client.send({
            from: fromAddress(),
            to: row.email,
            subject,
            content: body,
          });
          warned.push(row.profile_id);
        } catch (err) {
          // Left unstamped on purpose, so tomorrow's run tries again rather than treating this
          // person as warned.
          warnFailures++;
          console.error(`dormancy: could not warn ${row.profile_id}`, err);
        }
      }
      // Capped, not just caught: close() can block indefinitely rather than throw, which would
      // stall the whole run after the warnings had already gone out. See closeQuietly.
      await closeQuietly(client);
    }

    // Push is the courtesy copy — best effort, and never allowed to affect whether the account
    // counts as warned.
    for (const row of toWarn) {
      const { data: tokens } = await serviceClient
        .from("device_push_tokens")
        .select("apns_token, environment")
        .eq("profile_id", row.profile_id);

      for (const token of tokens ?? []) {
        try {
          await sendAPNs(
            token.apns_token,
            token.environment,
            row.stage === "warn_7" ? "Your account closes in 7 days" : "Your account closes in 30 days",
            "Open Twofold to keep your memories.",
            { route: "home" },
          );
        } catch (err) {
          console.error(`dormancy: push failed for ${row.profile_id}`, err);
        }
      }
    }

    if (warned.length > 0) {
      const { error: markErr } = await serviceClient.rpc("mark_dormancy_warned", {
        p_profile_ids: warned,
      });
      if (markErr) {
        // Every warned account will be warned again tomorrow. Annoying, not harmful — far better
        // than the alternative of losing the record and never warning them at all.
        console.error("dormancy: could not stamp warnings", markErr);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Closures
  // ---------------------------------------------------------------------------
  let closed = 0;
  let closeFailures = 0;

  for (const row of closing) {
    // Two steps, same order and same reasoning as `delete-account`: the RPC scrubs the profile and
    // dissolves the couple (starting the archive timer that actually deletes shared content), then
    // the admin API soft-deletes the auth row so sign-in is permanently disabled without
    // triggering the FK cascade that would take the other partner's history with it.
    const { error: closeErr } = await serviceClient.rpc("close_dormant_account", {
      p_profile_id: row.profile_id,
    });
    if (closeErr) {
      closeFailures++;
      console.error(`dormancy: could not close ${row.profile_id}`, closeErr);
      continue;
    }

    const { error: authErr } = await serviceClient.auth.admin.deleteUser(row.profile_id, true);
    if (authErr) {
      // The profile is scrubbed but the account can still be signed into. Both steps are
      // idempotent, so tomorrow's run finishes the job — except that the scrubbed profile now has
      // `account_deleted_at` set and so has left the cohort. Log loudly: this one needs a human.
      closeFailures++;
      console.error(
        `dormancy: scrubbed ${row.profile_id} but could not disable sign-in — needs a manual auth.admin.deleteUser`,
        authErr,
      );
      continue;
    }

    closed++;
  }

  return Response.json({
    warned: warned.length,
    warnFailures,
    closed,
    closeFailures,
    pendingClosures: capped ? toClose.length - closing.length : 0,
  });
});
