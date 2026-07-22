// Daily cleanup: archives game sessions where the invited partner never joined at all — a
// session sitting active for days with zero responses from the non-initiating partner just
// clutters the "waiting" list forever otherwise. Never touches a session either partner has
// actually engaged with, no matter how old. Cron-triggered only (see
// supabase/migrations/20260712170000_games_archive_cron_and_notif_prefs.sql).
//
// Requires the service-role key as a bearer token, same explicit check refresh-due-flights
// already uses — without this, any authenticated app user could invoke it directly and force a
// system-wide archive sweep on demand.

import { createClient } from "jsr:@supabase/supabase-js@2";

const STALE_AFTER_DAYS = 3;

Deno.serve(async (req) => {
  const expected = `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`;
  if (req.headers.get("Authorization") !== expected) {
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  }

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const staleCutoff = new Date(Date.now() - STALE_AFTER_DAYS * 24 * 60 * 60 * 1000).toISOString();

  const { data: candidates, error } = await serviceClient
    .from("game_sessions")
    .select("id, couple_id, initiator_id")
    .eq("status", "active")
    .lt("created_at", staleCutoff);

  if (error) {
    console.error("[archive-stale-games] failed to fetch candidates:", error.message);
    return Response.json({ error: error.message }, { status: 500 });
  }
  if (!candidates || candidates.length === 0) {
    return Response.json({ archived: 0 });
  }

  let archivedCount = 0;
  for (const session of candidates) {
    const { data: couple } = await serviceClient
      .from("couples")
      .select("partner_a_id, partner_b_id")
      .eq("id", session.couple_id)
      .maybeSingle();
    if (!couple) continue;

    const invitedPartnerId = couple.partner_a_id === session.initiator_id ? couple.partner_b_id : couple.partner_a_id;
    if (!invitedPartnerId) continue;

    const { count } = await serviceClient
      .from("game_responses")
      .select("id", { count: "exact", head: true })
      .eq("session_id", session.id)
      .eq("responder_id", invitedPartnerId);

    // The invited partner has answered at least one round — they've engaged, so this session
    // stays active no matter how old it is.
    if ((count ?? 0) > 0) continue;

    const { error: updateErr } = await serviceClient
      .from("game_sessions")
      .update({ status: "archived", updated_at: new Date().toISOString() })
      .eq("id", session.id);
    if (updateErr) {
      console.error(`[archive-stale-games] failed to archive session ${session.id}:`, updateErr.message);
      continue;
    }
    archivedCount++;
  }

  console.log(`[archive-stale-games] archived ${archivedCount} of ${candidates.length} stale candidate(s)`);
  return Response.json({ archived: archivedCount });
});
