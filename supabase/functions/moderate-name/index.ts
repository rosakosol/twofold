// Flags offensive/inappropriate names (slurs, harassment, etc.) using OpenAI's moderation
// endpoint, so onboarding can reject a bad name without the app shipping its own wordlist.
//
// Stateless — no DB read/write — callable with just the Supabase publishable (anon) key.
// Requires the OPENAI_API_KEY secret (already set for parse-flight-email).

import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";
import OpenAI from "openai";

const openai = new OpenAI({ apiKey: Deno.env.get("OPENAI_API_KEY") });

export default {
  fetch: withSupabase({ auth: ["publishable"] }, async (req, _ctx) => {
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
  }),
};

/* To invoke locally:

  1. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  2. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/moderate-name' \
    --header 'apiKey: sb_publishable_KvH6r2_haPL1sbAc1d4F-Q_5l1ImkpK' \
    --data '{"name":"Alex"}'

*/
