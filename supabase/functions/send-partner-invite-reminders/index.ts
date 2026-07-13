// Daily nudge for still-solo users (a profile with no active `couples` row referencing it) to
// invite their partner — two stages, day 1 and day 3 after signup. Cron-triggered only (see
// supabase/migrations/20260717020000_partner_invite_reminder_cron.sql); no auth header expected,
// same shape as send-streak-reminders/index.ts.
//
// Idempotency: each stage is bucketed by UTC calendar day (a profile created "yesterday" only
// ever matches the day-1 window on exactly one cron run, since the window shifts forward a full
// day between runs) rather than a precise 24h/72h offset — same simplicity tradeoff
// send-streak-reminders already makes with `todayStart`, and avoids needing to persist "already
// reminded" state anywhere.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { sendAPNs } from "../_shared/apns.ts";

type Stage = "day1" | "day3";

const MESSAGES: Record<Stage, { title: string; body: string }> = {
  day1: {
    title: "Set up Twofold together",
    body: "Invite your partner so you can start tracking flights, trips, and games together.",
  },
  day3: {
    title: "Still solo on Twofold?",
    body: "Invite your partner — it only takes a code to connect.",
  },
};

function utcDayStart(daysAgo: number): Date {
  const d = new Date();
  d.setUTCHours(0, 0, 0, 0);
  d.setUTCDate(d.getUTCDate() - daysAgo);
  return d;
}

Deno.serve(async (_req) => {
  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: activeCouples, error: couplesErr } = await serviceClient
    .from("couples")
    .select("partner_a_id, partner_b_id")
    .eq("status", "active");

  if (couplesErr) {
    console.error("[send-partner-invite-reminders] failed to fetch couples:", couplesErr.message);
    return Response.json({ error: couplesErr.message }, { status: 500 });
  }

  const pairedProfileIds = new Set<string>();
  for (const couple of activeCouples ?? []) {
    if (couple.partner_a_id) pairedProfileIds.add(couple.partner_a_id);
    if (couple.partner_b_id) pairedProfileIds.add(couple.partner_b_id);
  }

  let remindedCount = 0;

  for (const stage of ["day1", "day3"] as Stage[]) {
    const daysAgo = stage === "day1" ? 1 : 3;
    const windowStart = utcDayStart(daysAgo);
    const windowEnd = utcDayStart(daysAgo - 1);

    const { data: newProfiles, error: profilesErr } = await serviceClient
      .from("profiles")
      .select("id")
      .gte("created_at", windowStart.toISOString())
      .lt("created_at", windowEnd.toISOString());

    if (profilesErr) {
      console.error(`[send-partner-invite-reminders] failed to fetch ${stage} profiles:`, profilesErr.message);
      continue;
    }

    const soloProfileIds = (newProfiles ?? [])
      .map((row) => row.id as string)
      .filter((id) => !pairedProfileIds.has(id));

    if (soloProfileIds.length === 0) continue;

    const { data: prefRows } = await serviceClient
      .from("notification_preferences")
      .select("profile_id, partner_invite_reminder")
      .in("profile_id", soloProfileIds);

    const prefByProfile = new Map<string, boolean>();
    for (const row of prefRows ?? []) {
      prefByProfile.set(row.profile_id, Boolean(row.partner_invite_reminder));
    }
    // No preference row yet defaults to "notify" (matches the table's own column default).
    const allowedProfileIds = soloProfileIds.filter((id) => prefByProfile.get(id) ?? true);
    if (allowedProfileIds.length === 0) continue;

    const { data: tokens } = await serviceClient
      .from("device_push_tokens")
      .select("apns_token, environment")
      .in("profile_id", allowedProfileIds);
    if (!tokens || tokens.length === 0) continue;

    const { title, body } = MESSAGES[stage];
    for (const token of tokens) {
      try {
        await sendAPNs(token.apns_token, token.environment, title, body);
      } catch (err) {
        console.error("[send-partner-invite-reminders] sendAPNs threw:", (err as Error).message);
      }
    }
    remindedCount += allowedProfileIds.length;
  }

  console.log(`[send-partner-invite-reminders] reminded ${remindedCount} solo profile(s)`);
  return Response.json({ reminded: remindedCount });
});
