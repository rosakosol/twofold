// Deletes the R2 objects that a purged account or a purged couple left behind.
//
// Postgres cannot reach Cloudflare, so `purge_couple_data` and `private.scrub_account` write the
// keys into `pending_object_deletions` instead — before the cascade that removes the rows naming
// them — and this does the other half. See 20261110000000 for why the capture has to happen there
// rather than here.
//
// ---------------------------------------------------------------------------
// A key leaves the queue only when the object is gone
// ---------------------------------------------------------------------------
//
// `purge-support-attachments` deletes its rows first and treats a failed R2 delete as a logged
// leak. That is right for an abandoned screenshot. It is wrong here: these are photographs
// somebody asked us to delete, and the row that named each one is already gone, so a key dropped
// on the floor is unrecoverable without a bucket listing this codebase cannot perform.
//
// So nothing is removed from the queue that R2 has not confirmed. A failure records itself on the
// row and the next run tries again. `attempts` climbing is the signal that something needs a human;
// a key sitting at zero attempts has simply not been reached yet.
//
// ---------------------------------------------------------------------------
// dryRun
// ---------------------------------------------------------------------------
//
// `{"dryRun": true}` reports what it would delete and touches nothing. This exists because the
// first run of this function is the first time anything in Twofold has deleted a photograph
// nobody asked it to delete in that moment — the failure mode is somebody else's memories, which
// is worse than the leak being fixed. Fill the queue, read it back with dryRun, check the keys
// against a couple you control, then let it run.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { presign, r2ConfigFromEnv } from "../_shared/r2.ts";

/// Per invocation. The queue drains over several runs rather than holding one long request open,
/// and cron comes round again.
const BATCH = 500;

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405 });
  }

  let dryRun = false;
  try {
    const body = await req.json();
    dryRun = body?.dryRun === true;
  } catch {
    // No body is the cron case.
  }

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data, error } = await serviceClient
    .from("pending_object_deletions")
    .select("key, attempts")
    .order("enqueued_at", { ascending: true })
    .limit(BATCH);

  if (error) {
    console.error("[purge-r2-objects] could not read the queue:", error.message);
    return Response.json({ error: "Could not read the queue" }, { status: 500 });
  }

  const rows = (data ?? []) as { key: string; attempts: number }[];
  if (rows.length === 0) return Response.json({ ok: true, deleted: 0, failed: 0, remaining: 0 });

  if (dryRun) {
    return Response.json({ ok: true, dryRun: true, wouldDelete: rows.length, keys: rows.map((r) => r.key) });
  }

  let config;
  try {
    config = r2ConfigFromEnv();
  } catch (err) {
    // Nothing is dequeued. Unlike the support-attachment purge, a missing configuration here costs
    // only a delay: the keys are still in the table and the next run will find them.
    console.error("[purge-r2-objects] R2 is not configured:", (err as Error).message);
    return Response.json({ error: "Storage not configured", remaining: rows.length }, { status: 503 });
  }

  let deleted = 0;
  let failed = 0;

  for (const row of rows) {
    try {
      const url = await presign(config, row.key, { method: "DELETE", expiresIn: 120 });
      const response = await fetch(url, { method: "DELETE" });

      // 204 is a delete, 404 is an object that is already gone. Both mean it is not there, which is
      // what was asked for — and 404 is the normal case for a retried account deletion.
      if (response.ok || response.status === 404) {
        const { error: dequeueError } = await serviceClient
          .from("pending_object_deletions")
          .delete()
          .eq("key", row.key);
        if (dequeueError) {
          // The object is gone but the row stayed. Harmless: the next run re-issues a DELETE that
          // answers 404 and tries again to dequeue.
          console.error(`[purge-r2-objects] deleted the object but could not dequeue: ${dequeueError.message}`);
        }
        deleted++;
      } else {
        failed++;
        await noteFailure(serviceClient, row, `R2 returned ${response.status}`);
      }
    } catch (err) {
      failed++;
      await noteFailure(serviceClient, row, (err as Error).message);
    }
  }

  // Logged rather than silent, because a queue that stops draining is invisible otherwise — there
  // is no user-facing symptom of an object that should have been deleted and was not.
  if (failed > 0) {
    console.error(`[purge-r2-objects] ${failed} of ${rows.length} key(s) failed; they stay queued for the next run`);
  }

  return Response.json({ ok: true, deleted, failed, remaining: rows.length - deleted });
});

/// Records why a key is still here. The key itself is not logged: it contains the couple id and the
/// memory id, and this line would outlive the rows that held them.
// deno-lint-ignore no-explicit-any
async function noteFailure(client: any, row: { key: string; attempts: number }, reason: string) {
  await client
    .from("pending_object_deletions")
    .update({ attempts: row.attempts + 1, last_error: reason })
    .eq("key", row.key);
  console.error(`[purge-r2-objects] attempt ${row.attempts + 1} failed: ${reason}`);
}

/* To invoke locally:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/purge-r2-objects' \
    --header 'Authorization: Bearer <service-role-key>' \
    --header 'Content-Type: application/json' \
    --data '{"dryRun": true}'

*/
