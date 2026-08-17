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
// Each couple's day boundary is now real local midnight - the *later* of the two partners'
// midnights, so it never lands before either person's own (see
// 20260908000000_local_midnight_day_boundary.sql). That math lives in the database
// (`list_couple_day_bounds`), deliberately: it needs IANA timezone + DST handling, and
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

interface CoupleDayBounds {
  couple_id: string;
  partner_a_id: string | null;
  partner_b_id: string | null;
  local_date: string;
  next_boundary: string;
  current_streak: number;
  final_reminder_sent_date: string | null;
  early_reminder_sent_date: string | null;
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

  const { data: couples, error: couplesErr } = await serviceClient.rpc("list_couple_day_bounds");

  if (couplesErr) {
    console.error("[send-streak-reminders] failed to fetch couple day bounds:", couplesErr.message);
    return Response.json({ error: couplesErr.message }, { status: 500 });
  }
  const rows = (couples ?? []) as CoupleDayBounds[];
  if (rows.length === 0) {
    return Response.json({ reminded: 0 });
  }

  let remindedCount = 0;

  for (const couple of rows) {
    // Fires once, in the ~15-minute slot where "about `windowMinutes` left" first becomes true -
    // the window's width matches the cron's own cadence so no couple's boundary can slip through
    // uncaught between two runs, and the relevant dedup column stops a couple still inside that
    // window at the *next* run from being reminded twice for the same day.
    const minutesUntilBoundary = (new Date(couple.next_boundary).getTime() - now.getTime()) / 60_000;
    if (minutesUntilBoundary > windowMinutes || minutesUntilBoundary <= windowMinutes - CRON_INTERVAL_MINUTES) continue;
    if (couple[dedupColumn as keyof CoupleDayBounds] === couple.local_date) continue;

    const { data: todaysSession } = await serviceClient
      .from("game_sessions")
      .select("id")
      .eq("couple_id", couple.couple_id)
      .eq("is_daily", true)
      .eq("daily_local_date", couple.local_date)
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
    // answer today, so that's a stronger nudge than the generic copy below.
    const currentStreak = couple.current_streak ?? 0;

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
      .upsert({ couple_id: couple.couple_id, [dedupColumn]: couple.local_date }, { onConflict: "couple_id" });

    remindedCount++;
  }

  console.log(`[send-streak-reminders] reminded ${remindedCount} of ${rows.length} couple(s) (final=${isFinal})`);
  return Response.json({ reminded: remindedCount });
});
