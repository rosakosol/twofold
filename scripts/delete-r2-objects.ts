// Deletes a list of objects from R2, one key per line on stdin.
//
// Exists because nothing else removes them. R2 is not reachable from a foreign key, so deleting a
// profile, a couple or a memory takes the rows and leaves the bytes — the same gap
// `removeFlightDocumentObjects` and `deleteMemory` close for Supabase Storage, except those run
// inside the app and this is for cleanup done from a SQL editor.
//
// Keys, not prefixes. There is no list-objects call in `_shared/r2.ts` and adding one to support a
// destructive script is the wrong direction: every path is already recorded in the database
// (`profiles.avatar_path`, `memory_photos.photo_path`, `flight_documents.file_path`) or derivable
// from it (drawing pads), so the safe shape is to ask Postgres exactly what to delete and delete
// exactly that. A prefix delete would happily take a whole couple's photos on a typo.
//
//   psql "$DB" -t -A -f /tmp/tester-keys.sql | deno run --allow-env --allow-net --allow-read \
//     scripts/delete-r2-objects.ts --dry-run
//
// Drop --dry-run to actually delete. Needs the four R2_* values.

import { presign, r2ConfigFromEnv } from "../supabase/functions/_shared/r2.ts";

const DRY_RUN = Deno.args.includes("--dry-run");
const config = r2ConfigFromEnv();

const keys = (await new Response(Deno.stdin.readable).text())
  .split("\n")
  .map((line) => line.trim())
  .filter((line) => line.length > 0);

if (keys.length === 0) {
  console.log("No keys on stdin. Nothing to do.");
  Deno.exit(0);
}

// Refuses a key that is not under one of the four content prefixes. The input arrives through a
// pipe from a query someone wrote by hand, and a malformed line should not become a DELETE against
// something else in the bucket — `airline-logos` in particular sits alongside these and is not
// account-scoped.
const ALLOWED = ["avatars/", "drawing-pads/", "memory-photos/", "flight-documents/"];
const bad = keys.filter((key) => !ALLOWED.some((prefix) => key.startsWith(prefix)));
if (bad.length > 0) {
  console.error(`Refusing to run: ${bad.length} key(s) are not under a per-account prefix, e.g.`);
  for (const key of bad.slice(0, 5)) console.error(`  ${key}`);
  Deno.exit(1);
}

console.log(`${keys.length} object(s)${DRY_RUN ? " — dry run, nothing will be deleted" : ""}\n`);

let deleted = 0, missing = 0, failed = 0;

for (const key of keys) {
  try {
    if (DRY_RUN) {
      const head = await fetch(await presign(config, key, { method: "HEAD", expiresIn: 60 }), { method: "HEAD" });
      console.log(`  ${head.ok ? "would delete" : "not in R2   "}  ${key}`);
      head.ok ? deleted++ : missing++;
      continue;
    }
    const response = await fetch(await presign(config, key, { method: "DELETE", expiresIn: 60 }), { method: "DELETE" });
    // R2 answers 204 whether or not the object was there, which is the right semantics for a
    // delete and means a re-run after a partial failure is safe.
    if (!response.ok && response.status !== 404) throw new Error(`DELETE ${response.status}`);
    deleted++;
  } catch (error) {
    console.error(`  ${key}: ${(error as Error).message}`);
    failed++;
  }
}

console.log(
  `\n${DRY_RUN ? "would delete" : "deleted"} ${deleted}` +
    (DRY_RUN ? `, not present ${missing}` : "") +
    `, failed ${failed}`,
);
Deno.exit(failed > 0 ? 1 : 0);
