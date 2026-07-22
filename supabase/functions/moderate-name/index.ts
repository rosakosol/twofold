// Flags offensive/inappropriate names (slurs, harassment, etc.) using OpenAI's moderation
// endpoint, so onboarding can reject a bad name without the app shipping its own wordlist.
//
// Requires a real signed-in user (`Authorization: Bearer <user access token>`), not just the
// publishable/anon key — that key ships inside the app binary and is trivially extractable, and
// this function has no DB read/write to otherwise scope/rate-limit who can trigger a paid OpenAI
// call. Same fix, same reasoning as `parse-flight-email`. Requires the OPENAI_API_KEY secret
// (already set for parse-flight-email).

import { createClient } from "jsr:@supabase/supabase-js@2";
import OpenAI from "openai";

const openai = new OpenAI({ apiKey: Deno.env.get("OPENAI_API_KEY") });

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

  const { name } = await req.json();

  if (!name || typeof name !== "string" || name.trim().length === 0) {
    return Response.json({ error: "Missing 'name'" }, { status: 400 });
  }

  const moderation = await openai.moderations.create({
    model: "omni-moderation-latest",
    input: name,
  });

  const flagged = moderation.results.some((result) => result.flagged);
  return Response.json({ flagged });
});

/* To invoke locally:

  1. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  2. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/moderate-name' \
    --header 'apiKey: sb_publishable_KvH6r2_haPL1sbAc1d4F-Q_5l1ImkpK' \
    --header 'Authorization: Bearer <user-access-token>' \
    --data '{"name":"Alex"}'

*/
