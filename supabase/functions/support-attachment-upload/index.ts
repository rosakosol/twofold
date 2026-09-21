// Signs a one-off PUT so the console can put a file in R2 directly.
//
// The browser uploads to R2 rather than through here, because an edge function is a poor pipe: it
// would hold the whole file in memory on the way past for no benefit, and its request limits are
// tighter than the bucket's.
//
// ---------------------------------------------------------------------------
// The key is not the caller's to choose
// ---------------------------------------------------------------------------
//
// `reserve_support_attachment` mints it from the thread id and a fresh uuid, and this function
// signs only what that returned. A client-supplied key is a client-supplied path, and a presigned
// PUT for `../avatars/{someone}/avatar.jpg` is an endpoint for overwriting other people's files.
//
// The reservation also enforces the size ceiling, and the signature carries the content type — R2
// rejects an upload whose type does not match what was authorised, so a PUT signed for a PNG
// cannot be redeemed for something else.
//
// verify_jwt = true, and the role is checked against the CALLER's own client. A service-role client
// here would make the check pass for anybody.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { presign, r2ConfigFromEnv } from "../_shared/r2.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405 });
  }

  let input: { threadId?: string; filename?: string; contentType?: string; size?: number };
  try {
    input = await req.json();
  } catch {
    return Response.json({ error: "Invalid request" }, { status: 400 });
  }

  if (!input.threadId || !input.filename) {
    return Response.json({ error: "A conversation and a filename are required." }, { status: 400 });
  }

  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
  );

  const { data: { user } } = await userClient.auth.getUser();
  if (!user) return Response.json({ error: "Not authenticated" }, { status: 401 });

  const contentType = input.contentType?.trim() || "application/octet-stream";

  // Reserved with the caller's own client, so `is_support_admin()` inside sees them and the size
  // and count limits are applied to a real person rather than to the service role.
  const { data: reservation, error } = await userClient.rpc("reserve_support_attachment", {
    p_thread_id: input.threadId,
    p_filename: input.filename,
    p_content_type: contentType,
    p_size_bytes: input.size ?? 0,
  });

  if (error || !reservation) {
    // The message is the RPC's own — "attachments must be between 1 byte and 10MB", "too many
    // pending attachments" — which is more use to whoever is uploading than a generic refusal.
    return Response.json({ error: error?.message ?? "Could not reserve that upload." }, { status: 400 });
  }

  // deno-lint-ignore no-explicit-any
  const { id, key } = reservation as any;

  let uploadUrl: string;
  try {
    uploadUrl = await presign(r2ConfigFromEnv(), key, {
      method: "PUT",
      // Minutes, not hours. The browser uploads immediately; a URL that outlives the page is a
      // capability sitting in a history entry.
      expiresIn: 600,
      contentType,
    });
  } catch (err) {
    console.error("[support-attachment-upload] could not presign:", (err as Error).message);
    return Response.json({ error: "File storage isn't configured." }, { status: 503 });
  }

  return Response.json({ id, uploadUrl, contentType });
});
