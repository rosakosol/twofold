// Daily nudge: reminds couples who haven't answered today's Daily Activity question yet, so
// their streak doesn't lapse. Cron-triggered only - two schedules call this same function with
// different bodies, both every 15 minutes:
//   - `{}` (see supabase/migrations/20260713090000_streak_reminder_cron.sql,
//     20260905000000_early_streak_reminder_per_couple_boundary.sql): the early nudge, gated on
//     `daily_streak_reminder`, fired ~6 hours before each couple's own day boundary.
//   - `{"final": true}` (see 20260902000000_streak_ending_reminder_pref.sql,
//     20260904000000_streak_ending_reminder_per_couple_boundary.sql): a last-chance "1 hour left"
//     nudge, gated on `streak_ending_reminder`, fired ~1 hour before that same boundary.
//
// Each *partner* has their own day boundary - their own local midnight, not a shared couple-wide
// one (see 20260912000100_per_partner_day_boundaries.sql). A London/Melbourne couple is reminded
// nine hours apart, at 11pm each, rather than both at whichever midnight came first. That math
// lives in the database
// (`list_streak_reminder_targets`), deliberately: it needs IANA timezone + DST handling, and
// re-implementing that here in TypeScript would just be a second place to get it wrong. This
// function used to derive the boundary itself from `couples.created_at`, back when the day was
// anchored to whenever the couple happened to pair.
//
// Requires the service-role key as a bearer token, same explicit check refresh-due-flights
// already uses - without this, any authenticated app user could invoke it directly and force a
// push blast to every couple in the app on demand.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { sendAPNs } from "../_shared/apns.ts";

interface Input {
  final?: boolean;
}

// One row per person, not per couple. Each partner has their own local-midnight boundary now (see
// 20260912000100), so a London/Melbourne couple gets reminded nine hours apart — at 11pm each,
// rather than both at whichever partner's midnight came first.
interface StreakReminderTarget {
  profile_id: string;
  couple_id: string;
  partner_id: string | null;
  local_date: string;
  next_boundary: string;
  current_streak: number;
  early_reminder_sent_date: string | null;
  final_reminder_sent_date: string | null;
}

// The cron's own cadence - the "how long before the boundary" window below is exactly this wide,
// so a couple's qualifying moment always falls inside exactly one run, never split across two or
// skipped between them.
const CRON_INTERVAL_MINUTES = 15;

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
  const dedupColumn = isFinal ? "final_reminder_sent_date" : "early_reminder_sent_date";
  const windowMinutes = isFinal ? 60 : 360;

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const now = new Date();

  const { data: targets, error: targetsErr } = await serviceClient.rpc("list_streak_reminder_targets");

  if (targetsErr) {
    console.error("[send-streak-reminders] failed to fetch reminder targets:", targetsErr.message);
    return Response.json({ error: targetsErr.message }, { status: 500 });
  }
  const rows = (targets ?? []) as StreakReminderTarget[];
  if (rows.length === 0) {
    return Response.json({ reminded: 0 });
  }

  let remindedCount = 0;

  for (const target of rows) {
    // Fires once, in the ~15-minute slot where "about `windowMinutes` left" first becomes true -
    // the window's width matches the cron's own cadence so no boundary can slip through uncaught
    // between two runs, and the dedup row stops someone still inside that window at the *next* run
    // from being reminded twice for the same day.
    const minutesUntilBoundary = (new Date(target.next_boundary).getTime() - now.getTime()) / 60_000;
    if (minutesUntilBoundary > windowMinutes || minutesUntilBoundary <= windowMinutes - CRON_INTERVAL_MINUTES) continue;
    if (target[dedupColumn as keyof StreakReminderTarget] === target.local_date) continue;

    // The session for *this person's* day. Their partner may be on a different date entirely, and
    // will get their own row in this same loop when their own boundary comes around.
    const { data: todaysSession } = await serviceClient
      .from("game_sessions")
      .select("id")
      .eq("couple_id", target.couple_id)
      .eq("is_daily", true)
      .eq("daily_local_date", target.local_date)
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

    // Nothing to nudge this person about if they've already answered. Note this is about *them*,
    // not the couple: the streak needs both answers (advance_game_session's `v_both_complete`
    // gate), so the partner who hasn't answered is precisely the one whose silence breaks it — and
    // they're reminded on their own clock, not their partner's.
    if (answeredIds.has(target.profile_id)) continue;

    const { data: prefRows } = await serviceClient
      .from("notification_preferences")
      .select(`profile_id, ${prefColumn}`)
      .eq("profile_id", target.profile_id);

    // No preference row yet defaults to "notify" (matches the table's own column default).
    const prefRow = prefRows?.[0] as Record<string, unknown> | undefined;
    if (prefRow && !prefRow[prefColumn]) continue;

    const { data: tokens } = await serviceClient
      .from("device_push_tokens")
      .select("apns_token, environment")
      .eq("profile_id", target.profile_id);
    if (!tokens || tokens.length === 0) continue;

    // A streak in progress is worth naming explicitly - losing it is the whole reason to
    // answer today, so that's a stronger nudge than the generic copy below.
    const currentStreak = target.current_streak ?? 0;

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
          // The whole point of this nudge is "go answer today's question", so tapping it should
          // land there. No session id: this is scheduled from a cron before anyone has opened
          // (and therefore created) the day's session, so the app resolves it on arrival.
          { route: "daily_question" },
        );
      } catch (err) {
        console.error("[send-streak-reminders] sendAPNs threw:", (err as Error).message);
      }
    }

    // Per-profile, because two partners on different days would otherwise suppress each other if
    // this were still recorded once per couple.
    await serviceClient
      .from("streak_reminder_sends")
      .upsert({
        profile_id: target.profile_id,
        reminder_kind: isFinal ? "final" : "early",
        sent_for_date: target.local_date,
        updated_at: new Date().toISOString(),
      }, { onConflict: "profile_id,reminder_kind" });

    remindedCount++;
  }

  console.log(`[send-streak-reminders] reminded ${remindedCount} of ${rows.length} target(s) (final=${isFinal})`);
  return Response.json({ reminded: remindedCount });
});
