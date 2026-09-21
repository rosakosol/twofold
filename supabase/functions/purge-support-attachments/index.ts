// Deletes R2 objects for support attachments whose reply was never sent.
//
// Somebody picks a screenshot, changes their mind, closes the tab. The row and the object both
// survive with nothing pointing at them. `purge_dangling_support_attachments` removes the rows and
// hands back the keys; Postgres cannot reach R2, so this does the other half.
//
// Cron entrypoint (see 20261109002200), called with the service role key. Not meant to be reached
// by anything else — `verify_jwt = false` would make it public, so it is left requiring a JWT and
// the cron job supplies one.
//
// ---------------------------------------------------------------------------
// Rows first, objects second
// ---------------------------------------------------------------------------
//
// The RPC has already deleted the rows by the time this sees a key. That order is deliberate,
// because the two failure modes are not equal: a row gone whose object survives is a few kilobytes
// nobody can reach, while an object gone whose row survives is an attachment the console lists and
// a reply cannot fetch — failing a send at the moment somebody is answering a customer.
//
// So a failed delete here is a leak, knowingly accepted, and logged per key so a bucket filling up
// is visible rather than mysterious.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { presign, r2ConfigFromEnv } from "../_shared/r2.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405 });
  }

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data, error } = await serviceClient.rpc("purge_dangling_support_attachments", {
    p_older_than_hours: 24,
  });

  if (error) {
    console.error("[purge-support-attachments] could not collect keys:", error.message);
    return Response.json({ error: "Could not collect" }, { status: 500 });
  }

  const keys = ((data ?? []) as { r2_key: string }[]).map((row) => row.r2_key);
  if (keys.length === 0) {
    return Response.json({ ok: true, deleted: 0, failed: 0 });
  }

  let config;
  try {
    config = r2ConfigFromEnv();
  } catch (err) {
    // The rows are already gone. Say so plainly rather than reporting a clean failure, because the
    // objects are now unreachable and only a bucket listing will ever find them.
    console.error(
      `[purge-support-attachments] R2 is not configured; ${keys.length} object(s) are now orphaned:`,
      (err as Error).message,
    );
    return Response.json({ error: "Storage not configured", orphaned: keys.length }, { status: 503 });
  }

  let deleted = 0;
  let failed = 0;
  for (const key of keys) {
    try {
      const url = await presign(config, key, { method: "DELETE", expiresIn: 120 });
      const response = await fetch(url, { method: "DELETE" });
      // R2 answers 204 for a delete and 404 for an object already gone. Both mean it is not there,
      // which is the outcome asked for.
      if (response.ok || response.status === 404) {
        deleted++;
      } else {
        failed++;
        console.error(`[purge-support-attachments] R2 returned ${response.status} for ${key}`);
      }
    } catch (err) {
      failed++;
      // The key is logged because its row is gone: this line is the only remaining record that the
      // object exists at all.
      console.error(`[purge-support-attachments] could not delete ${key}:`, (err as Error).message);
    }
  }

  return Response.json({ ok: true, deleted, failed });
});

/* To invoke locally:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/purge-support-attachments' \
    --header 'Authorization: Bearer <service-role-key>' --data '{}'

*/
