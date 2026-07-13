// Daily nudge: reminds couples who haven't answered today's Daily Activity question yet, so
// their streak doesn't lapse. Cron-triggered only (see
// supabase/migrations/20260713090000_streak_reminder_cron.sql); no auth header expected — same
// shape as archive-stale-games/index.ts.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { sendAPNs } from "../_shared/apns.ts";

Deno.serve(async (_req) => {
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
      // A session already exists today — someone's engaged (advance_game_session only creates
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
      .select("profile_id, daily_streak_reminder")
      .in("profile_id", partnerIds);

    const prefByProfile = new Map<string, boolean>();
    for (const row of prefRows ?? []) {
      prefByProfile.set(row.profile_id, Boolean(row.daily_streak_reminder));
    }
    // No preference row yet defaults to "notify" (matches the table's own column default).
    const allowedPartnerIds = partnerIds.filter((id) => prefByProfile.get(id) ?? true);
    if (allowedPartnerIds.length === 0) continue;

    const { data: tokens } = await serviceClient
      .from("device_push_tokens")
      .select("apns_token, environment")
      .in("profile_id", allowedPartnerIds);
    if (!tokens || tokens.length === 0) continue;

    for (const token of tokens) {
      try {
        await sendAPNs(
          token.apns_token,
          token.environment,
          "Keep your streak going",
          "Today's question is waiting — answer it before the day ends.",
        );
      } catch (err) {
        console.error("[send-streak-reminders] sendAPNs threw:", (err as Error).message);
      }
    }
    remindedCount++;
  }

  console.log(`[send-streak-reminders] reminded ${remindedCount} of ${couples.length} couple(s)`);
  return Response.json({ reminded: remindedCount });
});
