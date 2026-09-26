// "Max's birthday is on Saturday", then "it's today" — pushed to the *partner*, never to the
// person whose birthday it is. Their own day is marked on screen when they open the app, and a
// notification telling somebody when they were born would be strange.
//
// Cron-triggered only, hourly (20261110001500). Hourly rather than daily because the whole point
// is each recipient's own local morning, and those are spread across every hour of the day — the
// query hands back everybody currently inside a birthday window, and this picks out the ones for
// whom it is morning right now.
//
// The two timezones in play are different on purpose, and `list_birthday_reminder_targets` is
// where that lives:
//
//   * `days_until` is measured in the *subject's* local calendar, so "it's today" means today
//     where they are. `Person.isBirthdayToday` on the client makes the same choice, so the push
//     and the in-app celebration never disagree.
//   * `recipient_local_hour` is the *recipient's*, because they are the one holding the phone.
//
// Requires the service-role key as a bearer token — the same explicit check every other
// cron-only function here uses. Without it any authenticated user could invoke this and blast a
// push at every couple in the app.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { sendAPNs } from "../_shared/apns.ts";

interface BirthdayReminderTarget {
  recipient_id: string;
  subject_id: string;
  subject_name: string | null;
  subject_birthday_month: number;
  subject_birthday_day: number;
  recipient_local_hour: number;
  days_until: number;
  upcoming_sent_for_year: number | null;
  today_sent_for_year: number | null;
  birthday_year: number;
}

/// Local morning. One hour wide, matching the cron's own cadence, so each recipient's morning
/// falls inside exactly one run — never split across two, never skipped between them. Same
/// reasoning as `send-streak-reminders`' window matching `CRON_INTERVAL_MINUTES`.
const REMINDER_LOCAL_HOUR = 9;

/// "on Saturday" reads better than "in 3 days" for anything inside a week, and it is the form
/// people use. Built from the subject's month/day rather than a parsed date, because that is all
/// that is stored — see migration 20261110001300 for why there is no year.
function weekdayName(month: number, day: number, year: number): string | null {
  const date = new Date(Date.UTC(year, month - 1, day));
  if (Number.isNaN(date.getTime())) return null;
  return date.toLocaleDateString("en-AU", { weekday: "long", timeZone: "UTC" });
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

  const { data: targets, error: targetsErr } = await serviceClient.rpc(
    "list_birthday_reminder_targets",
  );
  if (targetsErr) {
    console.error(
      "[send-birthday-reminders] failed to fetch targets:",
      targetsErr.message,
    );
    return Response.json({ error: targetsErr.message }, { status: 500 });
  }

  const rows = (targets ?? []) as BirthdayReminderTarget[];
  if (rows.length === 0) return Response.json({ reminded: 0 });

  let remindedCount = 0;

  for (const target of rows) {
    if (target.recipient_local_hour !== REMINDER_LOCAL_HOUR) continue;

    const kind = target.days_until === 0 ? "today" : "upcoming";
    const alreadySentFor = kind === "today"
      ? target.today_sent_for_year
      : target.upcoming_sent_for_year;
    // Rearms by itself next year, because the comparison is against this occurrence's year rather
    // than a bare "has sent" flag.
    if (alreadySentFor === target.birthday_year) continue;

    // Checked per recipient rather than filtered in the query, so a muted person still gets a
    // ledger row — otherwise unmuting mid-window would deliver a reminder for a day that has
    // already passed.
    const { data: prefs } = await serviceClient
      .from("notification_preferences")
      .select("partner_birthday_reminder")
      .eq("profile_id", target.recipient_id)
      .maybeSingle();
    const muted = prefs?.partner_birthday_reminder === false;

    if (!muted) {
      const name = target.subject_name?.trim() || "Your partner";
      const weekday = weekdayName(
        target.subject_birthday_month,
        target.subject_birthday_day,
        target.birthday_year,
      );
      const { title, body } = kind === "today"
        ? { title: "It's the day 🎂", body: `It's ${name}'s birthday today.` }
        : {
          title: "Coming up 🎂",
          body: weekday
            ? `${name}'s birthday is on ${weekday}.`
            : `${name}'s birthday is in ${target.days_until} days.`,
        };

      const { data: tokens } = await serviceClient
        .from("device_push_tokens")
        .select("apns_token, environment")
        .eq("profile_id", target.recipient_id);

      for (const token of tokens ?? []) {
        await sendAPNs(token.apns_token, token.environment, title, body, {
          eventType: `birthday_${kind}`,
        });
      }
      if ((tokens ?? []).length > 0) remindedCount++;
    }

    // Written whether or not anything was actually delivered — muted, or no devices registered.
    // The row records that this occurrence has been dealt with, which is what stops an hourly job
    // reconsidering the same person every hour for the rest of the day.
    const { error: ledgerErr } = await serviceClient
      .from("birthday_reminder_sends")
      .upsert({
        recipient_id: target.recipient_id,
        reminder_kind: kind,
        sent_for_year: target.birthday_year,
        updated_at: new Date().toISOString(),
      }, { onConflict: "recipient_id,reminder_kind" });
    if (ledgerErr) {
      console.error(
        "[send-birthday-reminders] could not record send:",
        ledgerErr.message,
      );
    }
  }

  return Response.json({ reminded: remindedCount });
});
