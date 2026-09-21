// Deletes the Supabase Storage originals left behind by the R2 migration, once the soak is over.
//
//   deno run --allow-env --allow-net --allow-read scripts/delete-storage-originals.ts            # dry run
//   deno run --allow-env --allow-net --allow-read scripts/delete-storage-originals.ts --confirm  # deletes
//
// Reads SUPABASE_URL and SUPABASE_SECRET_KEY (or SUPABASE_SERVICE_ROLE_KEY) from the environment,
// plus the R2_* set that `_shared/r2.ts` already expects. Note the project's *legacy* anon and
// service_role keys were disabled in July, so this needs a current `sb_secret_…` key.
//
// ---------------------------------------------------------------------------
// Through the Storage API, not the table
// ---------------------------------------------------------------------------
//
// `storage.objects` has a trigger, `storage.protect_delete()`, whose message is "Direct deletion
// from storage tables is not allowed. Use the Storage API instead" and whose hint is "This
// prevents accidental data loss from orphaned objects." It is right: the row's `version` column is
// the only thing mapping it to the file behind it, so deleting the row leaves the bytes on disk
// with nothing pointing at them and no way to find them again.
//
// Nine places in this repo switch that trigger off with `set_config('storage.allow_delete_query',
// 'true', true)` and delete rows directly, which means every account deletion since September has
// been orphaning these originals rather than removing them. This script does not add a tenth.
//
// ---------------------------------------------------------------------------
// It checks R2 first, which is the question the soak was asking
// ---------------------------------------------------------------------------
//
// The soak exists so that an original can be fetched back if a copy turned out to be wrong or
// missing. Ending it by deleting everything unconditionally answers that question by assuming it.
// So each original is only removed once a HEAD against R2 confirms the copy is really there, at
// the same key. Anything without a counterpart is left alone and listed at the end — that is
// precisely the file you would want the soak for, and it should be looked at rather than deleted
// on a schedule.

import { presign, r2ConfigFromEnv } from "../supabase/functions/_shared/r2.ts";

const BUCKETS = ["avatars", "drawing-pads", "memory-photos", "flight-documents"] as const;
/// The Storage API's list endpoint is per-prefix and not recursive, so folders are walked.
const PAGE = 100;

const confirm = Deno.args.includes("--confirm");
const projectUrl = Deno.env.get("SUPABASE_URL");
const secret = Deno.env.get("SUPABASE_SECRET_KEY") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!projectUrl || !secret) {
  console.error("SUPABASE_URL and SUPABASE_SECRET_KEY (or SUPABASE_SERVICE_ROLE_KEY) must be set");
  Deno.exit(1);
}
const r2 = r2ConfigFromEnv();

const headers = { apikey: secret, Authorization: `Bearer ${secret}`, "Content-Type": "application/json" };

interface StorageEntry {
  name: string;
  /// Null for a folder — the list endpoint returns both, distinguished only by this.
  id: string | null;
}

async function listRecursively(bucket: string, prefix = ""): Promise<string[]> {
  const keys: string[] = [];
  let offset = 0;

  while (true) {
    const response = await fetch(`${projectUrl}/storage/v1/object/list/${bucket}`, {
      method: "POST",
      headers,
      body: JSON.stringify({ prefix, limit: PAGE, offset, sortBy: { column: "name", order: "asc" } }),
    });
    if (!response.ok) {
      throw new Error(`list ${bucket}/${prefix} returned ${response.status}: ${await response.text()}`);
    }
    const page = await response.json() as StorageEntry[];
    if (page.length === 0) break;

    for (const entry of page) {
      const path = prefix ? `${prefix}/${entry.name}` : entry.name;
      if (entry.id === null) {
        keys.push(...await listRecursively(bucket, path));
      } else {
        keys.push(path);
      }
    }
    if (page.length < PAGE) break;
    offset += PAGE;
  }

  return keys;
}

/// Is this object already in R2, at the same key? A presigned HEAD answers without downloading.
async function existsInR2(key: string): Promise<boolean> {
  const url = await presign(r2, key, { method: "HEAD", expiresIn: 120 });
  const response = await fetch(url, { method: "HEAD" });
  if (response.status === 200) return true;
  if (response.status === 404) return false;
  throw new Error(`R2 HEAD for ${key} returned ${response.status}`);
}

let totalDeleted = 0;
const missing: string[] = [];

for (const bucket of BUCKETS) {
  const keys = await listRecursively(bucket);
  if (keys.length === 0) {
    console.log(`${bucket}: empty`);
    continue;
  }

  const safeToDelete: string[] = [];
  for (const key of keys) {
    // The R2 key carries the bucket as its first segment — see `PREFIX` in storage-url — while the
    // Storage path does not, so the two are not interchangeable and the prefix has to be added.
    if (await existsInR2(`${bucket}/${key}`)) {
      safeToDelete.push(key);
    } else {
      missing.push(`${bucket}/${key}`);
    }
  }

  console.log(
    `${bucket}: ${keys.length} object(s), ${safeToDelete.length} copied to R2, ${keys.length - safeToDelete.length} without a copy`,
  );

  if (!confirm || safeToDelete.length === 0) continue;

  // The Storage API takes a batch, and does the row and the file together — which is the whole
  // point of going through it rather than through Postgres.
  for (let i = 0; i < safeToDelete.length; i += PAGE) {
    const batch = safeToDelete.slice(i, i + PAGE);
    const response = await fetch(`${projectUrl}/storage/v1/object/${bucket}`, {
      method: "DELETE",
      headers,
      body: JSON.stringify({ prefixes: batch }),
    });
    if (!response.ok) {
      console.error(`  delete batch failed (${response.status}): ${await response.text()}`);
      continue;
    }
    totalDeleted += batch.length;
  }
  console.log(`  deleted ${safeToDelete.length}`);
}

if (missing.length > 0) {
  console.log(`\n${missing.length} object(s) have no counterpart in R2 and were NOT deleted:`);
  for (const key of missing) console.log(`  ${key}`);
  console.log("\nThese are the ones the soak was for. Check them before removing anything by hand.");
}

console.log(confirm ? `\nDone. Deleted ${totalDeleted}.` : "\nDry run. Re-run with --confirm to delete.");
