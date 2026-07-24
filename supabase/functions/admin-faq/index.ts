// Backs the Sanity Studio's custom "FAQ" tool (site/feedback/src/sanity/tools/FaqTool.tsx) —
// handles create/update/delete on the faq_entries table (see
// supabase/migrations/20260901001200_faq_entries.sql). Reads don't go through this function at
// all: faq_entries already has a public SELECT policy, so the Studio tool (and the marketing
// site's /faq page, and the iOS app's Support screen) all read it directly via Supabase's REST
// API with the anon/publishable key.
//
// Gated by a shared secret (`FAQ_ADMIN_SECRET`, sent as the `x-admin-secret` header) rather than
// a real user session — the Sanity Studio has no Supabase auth of its own to forward. This
// secret necessarily ends up embedded in the Studio's client-side bundle (as
// `NEXT_PUBLIC_FAQ_ADMIN_SECRET` in site/feedback), so it's only as safe as who's been granted
// access to the Sanity Studio itself — acceptable here since FAQ content isn't sensitive data,
// and reaching the Studio at all already requires a real Sanity account + project invite. Both
// env vars must be set to the same value:
//   - This function's Supabase secret: FAQ_ADMIN_SECRET
//   - site/feedback's Next.js env var (client-exposed by design): NEXT_PUBLIC_FAQ_ADMIN_SECRET
//
// Called directly from a browser (the Studio, unlike every other Edge Function in this project
// which is only ever called from the native Swift app or another server) — needs real CORS
// handling, including an OPTIONS preflight response, which nothing else here needed until now.

import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-admin-secret",
  "Access-Control-Allow-Methods": "POST, PATCH, DELETE, OPTIONS",
};

function jsonResponse(body: unknown, status = 200): Response {
  return Response.json(body, { status, headers: CORS_HEADERS });
}

interface FaqEntryInput {
  category?: string | null;
  question?: string;
  answer?: string;
  sortOrder?: number;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }

  const expectedSecret = Deno.env.get("FAQ_ADMIN_SECRET");
  if (!expectedSecret || req.headers.get("x-admin-secret") !== expectedSecret) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const id = new URL(req.url).searchParams.get("id");

  if (req.method === "POST") {
    let input: FaqEntryInput;
    try {
      input = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }
    if (!input.question?.trim() || !input.answer?.trim()) {
      return jsonResponse({ error: "'question' and 'answer' are required" }, 400);
    }
    const { data, error } = await serviceClient
      .from("faq_entries")
      .insert({
        category: input.category?.trim() || null,
        question: input.question.trim(),
        answer: input.answer.trim(),
        sort_order: input.sortOrder ?? 0,
      })
      .select()
      .single();
    if (error) {
      console.error("[admin-faq] insert failed:", error.message);
      return jsonResponse({ error: "Failed to create FAQ entry" }, 500);
    }
    return jsonResponse({ entry: data });
  }

  if (req.method === "PATCH") {
    if (!id) return jsonResponse({ error: "'id' query param is required" }, 400);
    let input: FaqEntryInput;
    try {
      input = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }
    const update: Record<string, unknown> = {};
    if (input.category !== undefined) update.category = input.category?.trim() || null;
    if (input.question !== undefined) update.question = input.question.trim();
    if (input.answer !== undefined) update.answer = input.answer.trim();
    if (input.sortOrder !== undefined) update.sort_order = input.sortOrder;
    const { data, error } = await serviceClient
      .from("faq_entries")
      .update(update)
      .eq("id", id)
      .select()
      .single();
    if (error) {
      console.error("[admin-faq] update failed:", error.message);
      return jsonResponse({ error: "Failed to update FAQ entry" }, 500);
    }
    return jsonResponse({ entry: data });
  }

  if (req.method === "DELETE") {
    if (!id) return jsonResponse({ error: "'id' query param is required" }, 400);
    const { error } = await serviceClient.from("faq_entries").delete().eq("id", id);
    if (error) {
      console.error("[admin-faq] delete failed:", error.message);
      return jsonResponse({ error: "Failed to delete FAQ entry" }, 500);
    }
    return jsonResponse({ success: true });
  }

  return jsonResponse({ error: "Method not allowed" }, 405);
});

/* To invoke locally:

  1. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  2. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/admin-faq' \
    --header 'apiKey: sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH' \
    --header 'x-admin-secret: <FAQ_ADMIN_SECRET>' \
    --data '{"category":"Getting started","question":"What is Twofold?","answer":"...","sortOrder":10}'

*/
