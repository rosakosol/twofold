// Removes a Live Activity's push token once it ends — called by LiveActivityManager.endActivity.
// Best-effort from the caller's point of view: the row would also naturally stop being useful
// once the flight itself is no longer actively tracked, but deleting it promptly avoids
// flight-sync.ts wasting a push attempt on a dead Activity.
//
// Requires an `Authorization: Bearer <user access token>` header (the caller's Supabase auth
// session). RLS already scopes the delete to `profile_id = auth.uid()`.

import { createClient } from "jsr:@supabase/supabase-js@2";

interface Input {
  activityId: string;
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
  if (!input?.activityId || typeof input.activityId !== "string") {
    return Response.json({ error: "'activityId' is required" }, { status: 400 });
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
    .delete()
    .eq("activity_id", input.activityId)
    .eq("profile_id", user.id);

  if (error) {
    console.error("[end-live-activity-token] delete failed:", error.message);
    return Response.json({ error: "Couldn't remove the Live Activity token" }, { status: 500 });
  }

  return Response.json({ ok: true });
});

/* To invoke locally:

  1. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  2. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/end-live-activity-token' \
    --header 'apiKey: sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH' \
    --header 'Authorization: Bearer <user-access-token>' \
    --data '{"activityId":"abc"}'

*/
