// Daily nudge: reminds couples who haven't answered today's Daily Activity question yet, so
// their streak doesn't lapse. Cron-triggered only - two schedules call this same function with
// different bodies:
//   - 18:00 UTC, `{}` (see supabase/migrations/20260713090000_streak_reminder_cron.sql): the
//     original early nudge, gated on `daily_streak_reminder`.
//   - 23:00 UTC, `{"final": true}` (see
//     supabase/migrations/20260902000000_streak_ending_reminder_pref.sql): a last-chance "1 hour
//     left" nudge, gated on the separate `streak_ending_reminder` column so a couple can turn
//     this one off independently of the earlier one.
//
// Requires the service-role key as a bearer token, same explicit check refresh-due-flights
// already uses - without this, any authenticated app user could invoke it directly and force a
// push blast to every couple in the app on demand.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { sendAPNs } from "../_shared/apns.ts";

interface Input {
  final?: boolean;
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

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const todayStart = new Date();
  todayStart.setUTCHours(0, 0, 0, 0);

  const { data: couples, error: couplesErr } = await serviceClient
    .from("couples")
    .select("id, partner_a_id, partner_b_id")
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
    const { data: todaysSession } = await serviceClient
      .from("game_sessions")
      .select("id")
      .eq("couple_id", couple.id)
      .eq("is_daily", true)
      .gte("created_at", todayStart.toISOString())
      .maybeSingle();

    if (todaysSession) {
      // A session already exists today - someone's engaged (advance_game_session only creates
      // daily_streaks rows on an actual response, and get_daily_question_session only creates
      // the session itself, so a session with no responses yet still needs a nudge).
      const { count } = await serviceClient
        .from("game_responses")
        .select("id", { count: "exact", head: true })
        .eq("session_id", todaysSession.id);
      if ((count ?? 0) > 0) continue;
    }

    const partnerIds = [couple.partner_a_id, couple.partner_b_id].filter((id): id is string => Boolean(id));
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
    const { data: streakRow } = await serviceClient
      .from("daily_streaks")
      .select("current_streak")
      .eq("couple_id", couple.id)
      .maybeSingle();
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
    remindedCount++;
  }

  console.log(`[send-streak-reminders] reminded ${remindedCount} of ${couples.length} couple(s) (final=${isFinal})`);
  return Response.json({ reminded: remindedCount });
});
