// Self-serve account deletion. Requires an `Authorization: Bearer <user access token>` header
// (the caller's own Supabase auth session) — deletes only the calling user's own account, never
// anyone else's.
//
// Two-step, in this order:
//   1. `delete_own_account()` (security definer RPC, runs as the caller) scrubs this user's own
//      identifying profile fields and storage objects, and dissolves any couple they're still
//      actively part of — see that migration's own header comment for exactly why this doesn't
//      just hard-delete the profile row outright (short version: the FK cascade from profiles to
//      couples would wipe the *other* partner's shared trip/memory history too).
//   2. `auth.admin.deleteUser(id, shouldSoftDelete: true)` — soft-deletes the actual `auth.users`
//      row: sign-in is permanently disabled and the account can never be recovered, but the row
//      itself is left in place (`deleted_at` set, not actually removed), so it never triggers
//      that same FK cascade. This step needs the service-role key, which is why it has to happen
//      here rather than directly from the client.
//
// If step 1 succeeds but step 2 fails, the account is left "scrubbed but still able to sign in" —
// the client should treat any error from this function as "please try again" rather than
// assuming nothing happened, and re-calling this function is always safe (both steps are
// idempotent).

import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405 });
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

  const { error: rpcError } = await userClient.rpc("delete_own_account");
  if (rpcError) {
    console.error("[delete-account] delete_own_account failed:", rpcError.message);
    return Response.json({ error: "Couldn't delete your account data. Please try again." }, { status: 500 });
  }

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { error: authError } = await serviceClient.auth.admin.deleteUser(user.id, true);
  if (authError) {
    console.error("[delete-account] auth.admin.deleteUser failed:", authError.message);
    return Response.json({ error: "Your data was deleted but signing out failed — please try again." }, { status: 500 });
  }

  return Response.json({ ok: true });
});

/* To invoke locally:

  1. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  2. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/delete-account' \
    --header 'apiKey: sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH' \
    --header 'Authorization: Bearer <user-access-token>'

*/
