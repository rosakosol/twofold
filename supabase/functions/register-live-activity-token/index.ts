// Upserts a Live Activity push token — called by LiveActivityManager whenever ActivityKit hands
// over a fresh token via `Activity.pushTokenUpdates`, which can fire more than once over an
// Activity's lifetime (not just at start). Keyed on `activity_id` (ActivityKit's own id) so a
// refreshed token for the same running Activity replaces the old row rather than duplicating it.
//
// Requires an `Authorization: Bearer <user access token>` header (the caller's Supabase auth
// session). RLS on `live_activity_push_tokens` already scopes writes to `profile_id = auth.uid()`,
// so this can safely use the user-scoped client for the whole request — no service role needed.

import { createClient } from "jsr:@supabase/supabase-js@2";

interface Input {
  flightId: string;
  activityId: string;
  pushToken: string;
  environment: "sandbox" | "production";
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405 });
  }

  let input: Input;
  try {
    input = await req.json();
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 });
  }
  if (!input?.flightId || !input?.activityId || !input?.pushToken) {
    return Response.json({ error: "'flightId', 'activityId', and 'pushToken' are required" }, { status: 400 });
  }
  if (input.environment !== "sandbox" && input.environment !== "production") {
    return Response.json({ error: "'environment' must be 'sandbox' or 'production'" }, { status: 400 });
  }

  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
  );

  const { data: { user } } = await userClient.auth.getUser();
  if (!user) {
    return Response.json({ error: "Not authenticated" }, { status: 401 });
  }

  const { error } = await userClient
    .from("live_activity_push_tokens")
    .upsert(
      {
        flight_id: input.flightId,
        profile_id: user.id,
        activity_id: input.activityId,
        push_token: input.pushToken,
        environment: input.environment,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "activity_id" },
    );

  if (error) {
    console.error("[register-live-activity-token] upsert failed:", error.message);
    return Response.json({ error: "Couldn't register the Live Activity token" }, { status: 500 });
  }

  return Response.json({ ok: true });
});

/* To invoke locally:

  1. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  2. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/register-live-activity-token' \
    --header 'apiKey: sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH' \
    --header 'Authorization: Bearer <user-access-token>' \
    --data '{"flightId":"00000000-0000-0000-0000-000000000000","activityId":"abc","pushToken":"deadbeef","environment":"sandbox"}'

*/
