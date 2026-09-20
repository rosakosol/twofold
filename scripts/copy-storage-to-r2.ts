// Copies every object out of Supabase Storage and into R2, keeping the same path.
//
// Run before the app is switched over. The paths in the database do not change — `photo_path` is
// still `{coupleID}/{memoryID}/{uuid}.jpg` — so all this does is put the bytes where the new code
// will look for them. The bucket name becomes the leading segment of the R2 key, which is the
// mapping `storage-url` applies when it presigns.
//
// Idempotent and resumable. Every object is HEADed in R2 first and skipped if it is already there
// with the same size, so a run that dies halfway can simply be run again, and a second run shortly
// before the cutover picks up anything written in between.
//
// Nothing is deleted from Supabase Storage. That stays as it is until the new build has been
// running for a while, because it is the only copy that exists if this turns out to be wrong.
//
//   deno run --allow-env --allow-net --allow-read scripts/copy-storage-to-r2.ts --dry-run
//   deno run --allow-env --allow-net --allow-read scripts/copy-storage-to-r2.ts
//
// Needs SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (service role, because these buckets are
// private and RLS would otherwise hide most of it), plus the four R2_* values.

// Storage's REST API directly rather than supabase-js: the SDK drags in npm dependencies that need
// a node_modules directory outside the Edge runtime, and this needs two endpoints. Same reason
// `r2.ts` signs by hand.
import { presign, type R2Config, r2ConfigFromEnv } from "../supabase/functions/_shared/r2.ts";

interface StorageEntry {
  name: string;
  /// Null for a folder. Supabase has no real directories, so this is the only way to tell.
  id: string | null;
  metadata: { size: number; mimetype: string } | null;
}

/// The four private buckets. `airline-logos` is deliberately absent: it is a cache of a public CDN
/// and is repopulated by scraping rather than copied, so moving its bytes would be wasted work.
const BUCKETS = ["avatars", "drawing-pads", "memory-photos", "flight-documents"];

const DRY_RUN = Deno.args.includes("--dry-run");

/// Supabase's list is per-prefix and returns folders as entries with a null id, so reaching every
/// object means walking the tree. A flat call would return the first level only — which, for these
/// buckets, is one entry per couple and not a single actual file.
///
/// Carries each object's size out with it, from the listing's own metadata, so the copy can decide
/// whether it needs the bytes at all before downloading them.
async function listRecursively(
  base: string,
  key: string,
  bucket: string,
  prefix: string,
  found: Array<{ path: string; size: number; type: string }> = [],
): Promise<Array<{ path: string; size: number; type: string }>> {
  let offset = 0;
  const limit = 100;
  while (true) {
    const response = await fetch(`${base}/storage/v1/object/list/${bucket}`, {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, "content-type": "application/json" },
      body: JSON.stringify({ prefix, limit, offset, sortBy: { column: "name", order: "asc" } }),
    });
    if (!response.ok) throw new Error(`list ${bucket}/${prefix}: ${response.status} ${await response.text()}`);
    const page = await response.json() as StorageEntry[];
    if (page.length === 0) break;
    for (const entry of page) {
      const path = prefix ? `${prefix}/${entry.name}` : entry.name;
      if (entry.id === null) await listRecursively(base, key, bucket, path, found);
      else {
        found.push({
          path,
          size: entry.metadata?.size ?? -1,
          type: entry.metadata?.mimetype || "application/octet-stream",
        });
      }
    }
    if (page.length < limit) break;
    offset += limit;
  }
  return found;
}

/// One object's bytes.
async function download(base: string, key: string, bucket: string, path: string): Promise<ArrayBuffer> {
  const encoded = path.split("/").map(encodeURIComponent).join("/");
  const response = await fetch(`${base}/storage/v1/object/${bucket}/${encoded}`, {
    headers: { Authorization: `Bearer ${key}` },
  });
  if (!response.ok) throw new Error(`download ${response.status}`);
  // ArrayBuffer, not Uint8Array: only the former is a BodyInit, and byteLength reads the same.
  return await response.arrayBuffer();
}

/// Already there, and the same size? Then this is a re-run, not a new object.
///
/// Size rather than a checksum on purpose: these are immutable once written (a new photo gets a new
/// uuid) except drawing pads, which are overwritten in place — and a pad that changed almost
/// certainly changed size. The cost of being wrong is one stale pad until the next save, against
/// downloading every object again on every run.
async function alreadyCopied(config: R2Config, key: string, size: number): Promise<boolean> {
  const url = await presign(config, key, { method: "HEAD", expiresIn: 60 });
  const response = await fetch(url, { method: "HEAD" });
  if (!response.ok) return false;
  const length = Number(response.headers.get("content-length") ?? "-1");
  return length === size;
}

/// Refuses to run with a key that is not service role.
///
/// This exists because of how the failure looks otherwise. Storage's list endpoint does not error
/// for a key that cannot see anything — RLS simply hides every row and it returns `[]`. So an anon
/// key produces "0 objects, 0 failed" across every bucket, which reads as a clean run against an
/// empty account rather than as a key problem, and the cutover then ships against an empty R2.
///
/// The legacy service-role key is a JWT whose payload carries `"role":"service_role"`, which is
/// cheap to check without verifying the signature — the server does that. A newer `sb_secret_...`
/// key is not a JWT and cannot be inspected here, so it is allowed through with a note.
function assertServiceRole(key: string): void {
  if (!key.startsWith("ey")) {
    console.log("Key is not a JWT (sb_secret_ style); cannot confirm it is service role.\n");
    return;
  }
  let role: string | undefined;
  try {
    const payload = key.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    role = JSON.parse(atob(payload + "=".repeat((4 - payload.length % 4) % 4))).role;
  } catch {
    throw new Error("SUPABASE_SERVICE_ROLE_KEY is not a readable JWT");
  }
  if (role !== "service_role") {
    throw new Error(
      `SUPABASE_SERVICE_ROLE_KEY carries role "${role}", not "service_role". An anon key sees ` +
        `nothing here and lists every bucket as empty, which looks like success. Use the legacy ` +
        `service_role JWT from Project Settings -> API -> Legacy API keys.`,
    );
  }
}

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (!supabaseUrl || !serviceKey) {
  console.error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required");
  Deno.exit(1);
}
assertServiceRole(serviceKey);
const base = supabaseUrl.replace(/\/$/, "");
const config = r2ConfigFromEnv();

console.log(DRY_RUN ? "DRY RUN — nothing will be written\n" : "Copying to R2\n");

let totalCopied = 0, totalSkipped = 0, totalFailed = 0, totalBytes = 0;

for (const bucket of BUCKETS) {
  let objects: Array<{ path: string; size: number; type: string }>;
  try {
    objects = await listRecursively(base, serviceKey, bucket, "");
  } catch (error) {
    console.error(`${bucket}: could not list — ${(error as Error).message}`);
    totalFailed++;
    continue;
  }

  let copied = 0, skipped = 0, failed = 0;
  for (const object of objects) {
    const key = `${bucket}/${object.path}`;
    try {
      // Checked before downloading, so a re-run costs one HEAD per object rather than the bytes.
      if (object.size >= 0 && await alreadyCopied(config, key, object.size)) {
        skipped++;
        continue;
      }
      if (DRY_RUN) {
        copied++;
        totalBytes += Math.max(object.size, 0);
        continue;
      }

      const bytes = await download(base, serviceKey, bucket, object.path);
      const put = await fetch(
        await presign(config, key, { method: "PUT", expiresIn: 300, contentType: object.type }),
        { method: "PUT", body: bytes, headers: { "content-type": object.type } },
      );
      if (!put.ok) throw new Error(`PUT ${put.status} ${await put.text()}`);
      copied++;
      totalBytes += bytes.byteLength;
    } catch (error) {
      console.error(`  ${key}: ${(error as Error).message}`);
      failed++;
    }
  }

  console.log(
    `${bucket.padEnd(18)} ${objects.length} objects — ${copied} copied, ${skipped} already there, ${failed} failed`,
  );
  totalCopied += copied;
  totalSkipped += skipped;
  totalFailed += failed;
}

console.log(
  `\n${DRY_RUN ? "would copy" : "copied"} ${totalCopied}, skipped ${totalSkipped}, failed ${totalFailed}` +
    ` (${(totalBytes / 1024 / 1024).toFixed(1)} MB)`,
);

// Every bucket empty is possible but unlikely on an account anyone has used, and it is exactly what
// a key without permission looks like. Say so rather than let a zero pass for a clean run.
if (totalCopied === 0 && totalSkipped === 0 && totalFailed === 0) {
  console.log(
    "\nNothing was found in any bucket. If that is unexpected, check in the SQL editor with:\n" +
      "  select bucket_id, count(*) from storage.objects group by 1 order by 1;",
  );
}
// Non-zero on failures, so this can be re-run until clean without reading the log.
Deno.exit(totalFailed > 0 ? 1 : 0);
