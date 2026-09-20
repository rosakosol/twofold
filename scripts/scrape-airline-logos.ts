// Fills R2 with airline logos, so the app stops depending on images.kiwi.com at request time.
//
// The `airline-logo` function will fetch a missing code from the CDN by itself and keep it, so this
// is a warming step rather than a prerequisite — but a warmed cache is the difference between
// "every logo we have ever needed is ours" and "the first person to fly a new carrier waits on a
// third party that owes us nothing".
//
//   deno run --allow-env --allow-net scripts/scrape-airline-logos.ts --dry-run
//   deno run --allow-env --allow-net scripts/scrape-airline-logos.ts
//   deno run --allow-env --allow-net scripts/scrape-airline-logos.ts --codes QF,SQ,NZ
//
// Codes come from the database: `airlines.iata`, which the flight lookups populate as they go, and
// the distinct `flights.airline_code` actually in use. `--codes` adds more by hand, for carriers
// worth having before anybody flies them.
//
// Needs SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY, plus the four R2_* values. Idempotent: a code
// already in R2 is skipped, so this can be re-run whenever the airline table grows.

import { presign, type R2Config, r2ConfigFromEnv } from "../supabase/functions/_shared/r2.ts";

const PREFIX = "airline-logos";
const CDN = (code: string) => `https://images.kiwi.com/airlines/64/${code}.png`;

const DRY_RUN = Deno.args.includes("--dry-run");

/// images.kiwi.com never 404s. An unknown code 303s to `/airlines/64x64/airlines.png`, a generic
/// placeholder, and a real one 303s to its own `64x64` file — so the status tells you nothing and
/// the redirect target tells you everything. Verified: QF lands on QF.png (2,524 bytes), while ZZZ
/// and QQQ both land on airlines.png with byte-identical content.
///
/// Caching that placeholder is worse than having nothing. It is indistinguishable from a real logo
/// once stored, it would be served forever under `immutable`, and it displaces the app's own
/// fallback with a stranger's house icon. The previous version of this cache stored it.
function isGenericPlaceholder(response: Response): boolean {
  try {
    return new URL(response.url).pathname.endsWith("/airlines.png");
  } catch {
    return false;
  }
}

/// Same validation the function applies, so this cannot warm a key the function would refuse to
/// look up.
function isValidIataCode(code: string): boolean {
  return /^[A-Z0-9]{2,3}$/.test(code);
}

function extraCodes(): string[] {
  const flag = Deno.args.find((arg) => arg.startsWith("--codes="));
  const inline = Deno.args[Deno.args.indexOf("--codes") + 1];
  const raw = flag ? flag.slice("--codes=".length) : (Deno.args.includes("--codes") ? inline : "");
  return raw ? raw.split(",").map((c) => c.trim().toUpperCase()).filter(Boolean) : [];
}

/// PostgREST directly rather than supabase-js, for the reason `copy-storage-to-r2.ts` gives: the
/// SDK needs npm dependencies resolved outside the Edge runtime, and this is two selects.
async function select(base: string, key: string, path: string): Promise<Array<Record<string, unknown>>> {
  const response = await fetch(`${base}/rest/v1/${path}`, {
    headers: { apikey: key, Authorization: `Bearer ${key}` },
  });
  if (!response.ok) throw new Error(`${path}: ${response.status} ${await response.text()}`);
  return await response.json();
}

async function alreadyStored(config: R2Config, code: string): Promise<boolean> {
  const url = await presign(config, `${PREFIX}/${code}.png`, { method: "HEAD", expiresIn: 60 });
  return (await fetch(url, { method: "HEAD" })).ok;
}

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (!supabaseUrl || !serviceKey) {
  console.error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required");
  Deno.exit(1);
}
const base = supabaseUrl.replace(/\/$/, "");
const config = r2ConfigFromEnv();

const codes = new Set<string>(extraCodes().filter(isValidIataCode));
for (const row of await select(base, serviceKey, "airlines?select=iata&iata=not.is.null")) {
  const code = String(row.iata ?? "").toUpperCase();
  if (isValidIataCode(code)) codes.add(code);
}
for (const row of await select(base, serviceKey, "flights?select=airline_code&airline_code=not.is.null")) {
  const code = String(row.airline_code ?? "").toUpperCase();
  if (isValidIataCode(code)) codes.add(code);
}

const sorted = [...codes].sort();
console.log(`${sorted.length} codes${DRY_RUN ? " (dry run — nothing will be written)" : ""}\n`);
if (sorted.length === 0) {
  console.log("Nothing to do. The airlines table fills in as flights are tracked; --codes seeds it by hand.");
  Deno.exit(0);
}

let stored = 0, skipped = 0, missing = 0, failed = 0;

for (const code of sorted) {
  try {
    if (await alreadyStored(config, code)) {
      skipped++;
      continue;
    }
    const upstream = await fetch(CDN(code));
    if (!upstream.ok || isGenericPlaceholder(upstream)) {
      // Normal, not an error: plenty of regional carriers have no logo there. Nothing is stored,
      // so one that gains a logo later gets picked up on the next run.
      console.log(`  ${code}: no logo upstream`);
      missing++;
      continue;
    }
    const bytes = await upstream.arrayBuffer();
    const contentType = upstream.headers.get("content-type") ?? "image/png";
    if (DRY_RUN) {
      stored++;
      continue;
    }
    const put = await fetch(
      await presign(config, `${PREFIX}/${code}.png`, { method: "PUT", expiresIn: 300, contentType }),
      { method: "PUT", body: bytes, headers: { "content-type": contentType } },
    );
    if (!put.ok) throw new Error(`PUT ${put.status}`);
    stored++;
  } catch (error) {
    console.error(`  ${code}: ${(error as Error).message}`);
    failed++;
  }
}

console.log(
  `\n${DRY_RUN ? "would store" : "stored"} ${stored}, already there ${skipped}, no logo upstream ${missing}, failed ${failed}`,
);
Deno.exit(failed > 0 ? 1 : 0);
