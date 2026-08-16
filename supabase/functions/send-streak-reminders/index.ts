// Daily nudge: reminds couples who haven't answered today's Daily Activity question yet, so
// their streak doesn't lapse. Cron-triggered only - two schedules call this same function with
// different bodies, both now every 15 minutes:
//   - `{}` (see supabase/migrations/20260713090000_streak_reminder_cron.sql,
//     20260905000000_early_streak_reminder_per_couple_boundary.sql): the early nudge, gated on
//     `daily_streak_reminder`, fired ~6 hours before each couple's own day boundary (originally a
//     single fixed 18:00 UTC, back when every couple's boundary was a shared UTC midnight and
//     18:00 really was "6 hours before the day ends" for everyone).
//   - `{"final": true}` (see supabase/migrations/20260902000000_streak_ending_reminder_pref.sql,
//     20260904000000_streak_ending_reminder_per_couple_boundary.sql): a last-chance "1 hour left"
//     nudge, gated on `streak_ending_reminder`, fired ~1 hour before that same boundary.
//
// Both windows are computed per couple (see `coupleDayBoundary`) rather than assuming a shared
// UTC boundary - 20260829000500_daily_streak_per_couple_boundary.sql moved the real streak/
// daily-question day boundary to be relative to each couple's own `couples.created_at`, so a
// single fixed send time for every couple could land anywhere from on-time to 23 hours off.
//
// Requires the service-role key as a bearer token, same explicit check refresh-due-flights
// already uses - without this, any authenticated app user could invoke it directly and force a
// push blast to every couple in the app on demand.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { sendAPNs } from "../_shared/apns.ts";

interface Input {
  final?: boolean;
}

const DAY_SECONDS = 86_400;
// The cron's own cadence - the "how long before the boundary" window below is exactly this wide,
// so a couple's qualifying moment always falls inside exactly one run, never split across two or
// skipped between them.
const CRON_INTERVAL_MINUTES = 15;

/// Each couple's own daily-question/streak "day" is a rolling 24h window anchored to
/// `couples.created_at`'s time-of-day (see 20260829000500_daily_streak_per_couple_boundary.sql),
/// not a shared calendar day - a couple who connected at 14:00 UTC has their day roll over at
/// 14:00 UTC every day, not midnight. `dayIndex`/`dayStart`/`dayBoundary` mirror the exact
/// `floor(extract(epoch from (now() - created_at)) / 86400)` math the database functions
/// (advance_game_session, get_daily_question_session/_status) already use, so "today" here always
/// means the same window those do.
function coupleDayBoundary(createdAt: Date, now: Date) {
  const dayIndex = Math.floor((now.getTime() - createdAt.getTime()) / 1000 / DAY_SECONDS);
  const dayStart = new Date(createdAt.getTime() + dayIndex * DAY_SECONDS * 1000);
  const dayBoundary = new Date(createdAt.getTime() + (dayIndex + 1) * DAY_SECONDS * 1000);
  return { dayIndex, dayStart, dayBoundary };
}

Deno.serve(async (req) => {
  const expected = `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`;
  if (req.headers.get("Authorization") !== expected) {
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  }

  let input: Input = {};
  try {
    const text = await req.text();
    if (text) input = JSON.parse(text);
  } catch {
    // Malformed body falls back to the original early-reminder behavior rather than failing
    // the whole cron run over it.
  }
  const isFinal = input.final === true;
  const prefColumn = isFinal ? "streak_ending_reminder" : "daily_streak_reminder";
  const dedupColumn = isFinal ? "final_reminder_sent_day_index" : "early_reminder_sent_day_index";
  // "1 hour left" vs. the original 18:00-UTC-when-the-boundary-was-midnight-UTC nudge, which was
  // always really "6 hours before the day ends" - same relationship, now measured against each
  // couple's own boundary instead of assuming everyone's is midnight.
  const windowMinutes = isFinal ? 60 : 360;

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const now = new Date();

  const { data: couples, error: couplesErr } = await serviceClient
    .from("couples")
    .select("id, partner_a_id, partner_b_id, created_at")
    .eq("status", "active");

  if (couplesErr) {
    console.error("[send-streak-reminders] failed to fetch couples:", couplesErr.message);
    return Response.json({ error: couplesErr.message }, { status: 500 });
  }
  if (!couples || couples.length === 0) {
    return Response.json({ reminded: 0 });
  }

  let remindedCount = 0;

  for (const couple of couples) {
    const { dayIndex, dayStart, dayBoundary } = coupleDayBoundary(new Date(couple.created_at), now);

    const { data: streakRow } = await serviceClient
      .from("daily_streaks")
      .select("current_streak, final_reminder_sent_day_index, early_reminder_sent_day_index")
      .eq("couple_id", couple.id)
      .maybeSingle();

    // Fires once, in the ~15-minute slot where "about `windowMinutes` left" first becomes true -
    // the window's width matches the cron's own cadence so no couple's boundary can slip through
    // uncaught between two runs, and the relevant dedup column stops a couple still inside that
    // window at the *next* run from being reminded twice for the same day.
    const minutesUntilBoundary = (dayBoundary.getTime() - now.getTime()) / 60_000;
    if (minutesUntilBoundary > windowMinutes || minutesUntilBoundary <= windowMinutes - CRON_INTERVAL_MINUTES) continue;
    if ((streakRow as Record<string, unknown> | null)?.[dedupColumn] === dayIndex) continue;

    const { data: todaysSession } = await serviceClient
      .from("game_sessions")
      .select("id")
      .eq("couple_id", couple.id)
      .eq("is_daily", true)
      .gte("created_at", dayStart.toISOString())
      .lt("created_at", dayBoundary.toISOString())
      .maybeSingle();

    // Who has personally answered today. Keeping the *set* rather than a bare count is the fix
    // for a real bug: the streak only advances once *both* partners have answered (see
    // advance_game_session's `v_both_complete` gate), so "somebody answered" never meant the
    // couple was safe. Skipping the whole couple on the first response meant the partner who
    // hadn't answered - precisely the person whose silence is about to break the streak - was the
    // one guaranteed never to get the "1 hour left!" nudge.
    // (advance_game_session only creates daily_streaks rows on an actual response, and
    // get_daily_question_session only creates the session itself, so a session with no responses
    // yet still needs a nudge - handled naturally by the empty set below.)
    const answeredIds = new Set<string>();
    if (todaysSession) {
      const { data: responses } = await serviceClient
        .from("game_responses")
        .select("responder_id")
        .eq("session_id", todaysSession.id);
      for (const row of responses ?? []) answeredIds.add(row.responder_id as string);
    }

    // Only partners who still owe an answer. Empty means both are done - the streak is safe for
    // today, so there's nothing to remind anyone about.
    const partnerIds = [couple.partner_a_id, couple.partner_b_id]
      .filter((id): id is string => Boolean(id))
      .filter((id) => !answeredIds.has(id));
    if (partnerIds.length === 0) continue;

    const { data: prefRows } = await serviceClient
      .from("notification_preferences")
      .select(`profile_id, ${prefColumn}`)
      .in("profile_id", partnerIds);

    const prefByProfile = new Map<string, boolean>();
    for (const row of prefRows ?? []) {
      prefByProfile.set(row.profile_id, Boolean((row as Record<string, unknown>)[prefColumn]));
    }
    // No preference row yet defaults to "notify" (matches the table's own column default).
    const allowedPartnerIds = partnerIds.filter((id) => prefByProfile.get(id) ?? true);
    if (allowedPartnerIds.length === 0) continue;

    const { data: tokens } = await serviceClient
      .from("device_push_tokens")
      .select("apns_token, environment")
      .in("profile_id", allowedPartnerIds);
    if (!tokens || tokens.length === 0) continue;

    // A streak in progress is worth naming explicitly - losing it is the whole reason to
    // answer today, so that's a stronger nudge than the generic copy below. current_streak
    // still reflects the streak as of the couple's last answered day (advance_game_session
    // only resets it once a day is actually missed), so it's exactly "the streak they stand
    // to lose if they skip today."
    const currentStreak = streakRow?.current_streak ?? 0;

    const title = isFinal ? "1 hour left!" : "Keep your streak going";
    const body = isFinal
      ? (currentStreak > 0
        ? `Only 1 hour left to keep your ${currentStreak} day streak - answer today's question now 🔥`
        : "Only 1 hour left today - answer now before the day ends.")
      : (currentStreak > 0
        ? `You're on a ${currentStreak} day streak - answer today's question to keep it going 🔥`
        : "Today's question is waiting - answer it before the day ends.");

    for (const token of tokens) {
      try {
        await sendAPNs(
          token.apns_token,
          token.environment,
          title,
          body,
        );
      } catch (err) {
        console.error("[send-streak-reminders] sendAPNs threw:", (err as Error).message);
      }
    }

    await serviceClient
      .from("daily_streaks")
      .upsert({ couple_id: couple.id, [dedupColumn]: dayIndex }, { onConflict: "couple_id" });

    remindedCount++;
  }

  console.log(`[send-streak-reminders] reminded ${remindedCount} of ${couples.length} couple(s) (final=${isFinal})`);
  return Response.json({ reminded: remindedCount });
});
