// The server-side writer for `profiles.subscription_active` / `subscription_tier` /
// `subscription_checked_at`. RevenueCat calls this; the app never does.
//
// Until now those three columns were written by the device itself — BackendService.swift's
// `updateSubscriptionStatus` PATCHed the caller's own profile row with whatever the local StoreKit
// read said. That made the client the source of truth for entitlement, which is to say anyone with
// curl and the anon key that ships in the app could grant themselves (and, via
// `private.couple_effective_tier`, their partner) Premium. Migration
// 20260915000000_lock_subscription_columns_from_clients.sql closes that with a BEFORE trigger that
// rejects any write to those columns from `anon`/`authenticated`. This function is the replacement
// writer, running as service_role, and it has to exist and be verified *before* that migration
// ships — otherwise a new subscriber pays and nothing records it.
//
// ---------------------------------------------------------------------------
// Why the event type is deliberately ignored
// ---------------------------------------------------------------------------
//
// The obvious handler switches on `event.type` — INITIAL_PURCHASE/RENEWAL/UNCANCELLATION mean
// active, EXPIRATION means inactive, and so on. That handler is wrong, and wrong in a way that only
// shows up in production. There are a dozen-plus event types (PRODUCT_CHANGE, SUBSCRIPTION_PAUSED,
// BILLING_ISSUE, TRANSFER, SUBSCRIPTION_EXTENDED, TEMPORARY_ENTITLEMENT_GRANT…), each needing its
// own correct mapping; deliveries are retried, so the same event arrives more than once; and
// nothing guarantees ordering, so an EXPIRATION for a lapsed plan can land *after* the
// INITIAL_PURCHASE for the plan that replaced it and leave a paying customer locked out.
//
// So the event body is used for exactly one thing: working out *which* subscriber changed. The
// actual state is then read back from RevenueCat's REST API
// (`GET /v1/subscribers/{app_user_id}`), and whatever that says is what gets written. The handler
// is idempotent and order-independent by construction rather than by careful case analysis — two
// redeliveries of the same event write the same row twice with the same values, and a reordered
// pair converges on current truth because both read current truth. The cost is one extra HTTPS call
// per delivery, which is the right trade for not having to reason about ordering at all.
//
// Tier resolution mirrors `SubscriptionTier.active(in:)` in SubscriptionStore.swift exactly:
// Premium wins if both entitlements are somehow active at once. That is not hypothetical — if the
// four products ever sit in separate App Store Connect subscription groups (a bug this app has
// already hit, see git history around 2026-07-25) Apple does not auto-replace on plan switch, both
// subscriptions keep billing, and RevenueCat correctly reports both entitlements active.
//
// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------
//
// RevenueCat sends a fixed `Authorization` header value, set in its dashboard, which must match the
// `REVENUECAT_WEBHOOK_SECRET` secret here. That is the whole of the authentication — there is no
// signature to verify — so it is compared in constant time via `timingSafeEqual` below rather than
// with `!==`. (The sibling `aeroapi-webhook` compares its token with `!==`; that is not a pattern to
// copy. A plain string comparison bails at the first differing byte, and the timing difference is
// measurable across enough requests, which is how a shared secret gets recovered a byte at a time
// from an endpoint that anyone on the internet can hammer.)
//
// `verify_jwt = false` in config.toml, same as aeroapi-webhook and admin-faq: RevenueCat has no
// Supabase session and cannot send a JWT, so the platform-level check has to be off and the header
// check below is what actually guards the endpoint.
//
// No CORS block, unlike admin-faq — nothing in a browser calls this, and answering a preflight
// would only widen what can reach the secret check.
//
// Requires these Supabase secrets:
//   - REVENUECAT_WEBHOOK_SECRET — the exact Authorization header value configured on the
//     RevenueCat webhook (must match byte for byte, including any "Bearer " prefix if one is used).
//   - REVENUECAT_REST_API_KEY   — a RevenueCat *secret* API key (v1 REST). Never the `appl_...`
//     public SDK key in RevenueCatConfig.swift, which cannot read subscriber state.

import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  describeMissingStart,
  resolveStartedAt,
  resolveTier,
  type RestSubscriber,
  type Tier,
} from "./subscriber.ts";

const REVENUECAT_API_BASE = "https://api.revenuecat.com/v1";

// A `subscription_checked_at` further ahead than this can't have come from us (we only ever write
// RevenueCat's own clock, which is never meaningfully ahead of now) — it's a leftover from the old
// client-written era, stamped by a device with a wrong clock. Without this escape hatch the
// staleness guard below would treat such a row as permanently newer than every webhook and the
// profile would never be writable again.
const FUTURE_STAMP_SLACK_MS = 5 * 60 * 1000;

// ASSUMED payload shape, not verified against a live delivery: RevenueCat posts
// `{ "api_version": "1.0", "event": { "type": ..., "app_user_id": ..., ... } }`. Everything is
// optional here and read defensively — the only field this function actually needs is some
// identifier, and it will happily find one at the top level too if the envelope ever changes.
interface WebhookEvent {
  type?: string;
  app_user_id?: string;
  original_app_user_id?: string;
  aliases?: unknown;
  transferred_from?: unknown;
  transferred_to?: unknown;
  [key: string]: unknown;
}

interface WebhookPayload {
  event?: WebhookEvent;
  [key: string]: unknown;
}

interface RestSubscriberResponse {
  request_date?: string;
  request_date_ms?: number;
  subscriber?: RestSubscriber;
}

function jsonResponse(body: unknown, status = 200): Response {
  return Response.json(body, { status });
}

// Constant-time string comparison. Hashing both sides first is what lets this handle unequal
// lengths without an early return: SHA-256 digests are always 32 bytes, so the loop below runs the
// same number of iterations and touches the same memory no matter how wrong the candidate is, and
// the digest of a wrong secret reveals nothing about the right one.
async function timingSafeEqual(a: string, b: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const [aHash, bHash] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(a)),
    crypto.subtle.digest("SHA-256", encoder.encode(b)),
  ]);
  const aBytes = new Uint8Array(aHash);
  const bBytes = new Uint8Array(bHash);
  let diff = 0;
  for (let i = 0; i < aBytes.length; i++) diff |= aBytes[i] ^ bBytes[i];
  return diff === 0;
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

// Swift's `UUID.uuidString` uppercases, and AppModel.swift:609 passes exactly that to
// `Purchases.shared.logIn`, so every real app_user_id arrives uppercase while Postgres stores the
// lowercase form. Normalising here keeps the comparison textual and obvious rather than relying on
// Postgres's uuid parser to be case-insensitive on our behalf.
function normalizeUserId(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const candidate = value.trim().toLowerCase();
  return UUID_PATTERN.test(candidate) ? candidate : null;
}

// Everything in the event that might name a subscriber, deduped and filtered to real UUIDs.
//
// Two cases make this worth doing properly rather than just reading `app_user_id`:
//
//   - A purchase made before sign-in is attributed to an `$RCAnonymousID:...`, and the real UUID
//     shows up in `aliases` (or as `original_app_user_id`) once `logIn` aliases the two. Reading
//     only `app_user_id` there would silently drop the one delivery that matters.
//   - TRANSFER moves entitlements between ids, so *both* sides need re-reading: the id that gained
//     them and the id that lost them. Syncing only one leaves the other showing a subscription it
//     no longer has.
//
// Anything that isn't a UUID — anonymous ids included — is simply not in the returned list, which
// is what makes the "ignore anonymous ids" rule fall out for free rather than needing its own check.
function collectCandidateUserIds(event: WebhookEvent): string[] {
  const raw: unknown[] = [event.app_user_id, event.original_app_user_id];
  for (const list of [event.aliases, event.transferred_from, event.transferred_to]) {
    if (Array.isArray(list)) raw.push(...list);
  }
  const ids = new Set<string>();
  for (const value of raw) {
    const id = normalizeUserId(value);
    if (id) ids.add(id);
  }
  return [...ids];
}

interface SubscriberState {
  tier: Tier;
  /// When the current subscription was originally bought, or null if there isn't one or RevenueCat
  /// didn't say. Only ever used to work out which partner of two subscribers bought later; see
  /// `resolveStartedAt`.
  startedAt: string | null;
  /// RevenueCat's own clock at the moment it computed this state. Used as the row's
  /// `subscription_checked_at`, which makes the staleness comparison in applyState a comparison
  /// between two readings of a single clock rather than between our clock and theirs.
  asOfMs: number;
}

/// `null` means "RevenueCat has never heard of this id" — see the 404 branch.
/// Throws for anything retryable; the caller turns that into a 5xx so RevenueCat redelivers.
async function fetchSubscriberState(appUserId: string, apiKey: string): Promise<SubscriberState | null> {
  const response = await fetch(`${REVENUECAT_API_BASE}/subscribers/${encodeURIComponent(appUserId)}`, {
    headers: { Authorization: `Bearer ${apiKey}`, Accept: "application/json" },
  });

  // A subscriber RevenueCat has no record of, despite an event naming them. Contradictory enough
  // that it's treated as a no-op rather than as proof of "no entitlements" — writing
  // active = false off the back of a 404 would revoke a real subscription on the strength of a
  // response that shouldn't have happened. A genuinely entitlement-less id (the losing side of a
  // TRANSFER, say) comes back 200 with an empty or fully-expired entitlements map, which is
  // handled properly below.
  if (response.status === 404) return null;

  // 429 and 5xx are transient; anything else here (401 from a bad/rotated key, 403) is a
  // misconfiguration that retrying won't fix — but there's no correct state to write either way, so
  // both throw and let RevenueCat retry. A permanently broken key needs a human, and repeated
  // deliveries failing loudly is the signal that gets one.
  if (!response.ok) {
    throw new Error(`RevenueCat API returned ${response.status}`);
  }

  const body = await response.json() as RestSubscriberResponse;
  const subscriber = body.subscriber ?? {};
  const entitlements = subscriber.entitlements ?? {};

  // Prefer RevenueCat's stamp for this reading; fall back to ours only if it's missing, which just
  // degrades the staleness guard to a same-clock approximation rather than breaking it.
  const asOfMs = typeof body.request_date_ms === "number"
    ? body.request_date_ms
    : typeof body.request_date === "string" && !Number.isNaN(Date.parse(body.request_date))
    ? Date.parse(body.request_date)
    : Date.now();

  const tier = resolveTier(entitlements, asOfMs);
  const startedAt = resolveStartedAt(subscriber, tier);

  // An active subscriber whose start date could not be found. Logged with field names only, never
  // values, because `resolveStartedAt`'s reading of the v1 shape has never been checked against a
  // real response — this is the line that turns that assumption into something answerable.
  if (tier !== null && startedAt === null) {
    console.warn(`[revenuecat-webhook] no purchase date for ${appUserId}: ${describeMissingStart(subscriber, tier)}`);
  }

  return { tier, startedAt, asOfMs };
}

type ApplyOutcome = "written" | "no_profile" | "stale";

async function applyState(
  // deno-lint-ignore no-explicit-any
  serviceClient: any,
  appUserId: string,
  state: SubscriberState,
): Promise<ApplyOutcome> {
  const { data: profile } = await serviceClient
    .from("profiles")
    .select("id")
    .eq("id", appUserId)
    .maybeSingle();

  // A valid UUID with no profile row — a deleted account, or a different Supabase project pointed
  // at the same RevenueCat app. Nothing to write, and nothing a retry would fix.
  if (!profile) return "no_profile";

  const stateAsOf = new Date(state.asOfMs).toISOString();
  const futureCutoff = new Date(Date.now() + FUTURE_STAMP_SLACK_MS).toISOString();

  // The staleness guard, expressed as part of the UPDATE rather than as a read-then-write. Two
  // deliveries for one subscriber can be in flight at once (RevenueCat fans out events, and a
  // redelivery can overlap the original), and both will have called fetchSubscriberState against
  // different instants. Whichever reading is older must not be the one that lands last. Checking
  // the stored timestamp in a separate SELECT would just move the race; making it a WHERE clause on
  // the UPDATE makes it a genuine compare-and-set, decided by Postgres under the row lock.
  //
  // This is also why `subscription_checked_at` holds RevenueCat's `request_date` rather than our
  // own now(): the column then means "the state here is RevenueCat's as of this instant", so the
  // comparison never crosses clocks. In practice the two are seconds apart, and the column's only
  // consumer is freshness reasoning, so nothing downstream can tell the difference.
  //
  // The third disjunct is the escape hatch for future-dated stamps left by the old client-side
  // writer; see FUTURE_STAMP_SLACK_MS.
  const freshnessGuard = [
    "subscription_checked_at.is.null",
    `subscription_checked_at.lt."${stateAsOf}"`,
    `subscription_checked_at.gt."${futureCutoff}"`,
  ].join(",");

  const { data: updated, error } = await serviceClient
    .from("profiles")
    .update({
      subscription_active: state.tier !== null,
      subscription_tier: state.tier,
      subscription_checked_at: stateAsOf,
      // Cleared along with the tier when a subscription lapses, so a stale start date can't
      // outlive the subscription it belonged to and make someone look like the later buyer years
      // after they stopped paying.
      subscription_started_at: state.startedAt,
    })
    .eq("id", appUserId)
    .or(freshnessGuard)
    .select("id");

  if (error) throw new Error(`profile update failed: ${error.message}`);

  // The row exists (checked above) but matched nothing, so the guard is what rejected it: a newer
  // reading already landed. Correct outcome, not a failure — do not retry.
  return (updated?.length ?? 0) > 0 ? "written" : "stale";
}

/// Appends what we decided to `subscription_events` (20260926000000).
///
/// Exists because entitlement is read as an OR across both partners' profiles, so "why is this
/// couple Premium?" is otherwise a guess — neither row records where its value came from. Recorded
/// for every outcome, not just successful writes: a run of `stale` is what out-of-order delivery
/// looks like from the outside, and `no_profile` is how a deleted account shows up.
///
/// Never allowed to fail the request. This is a ledger, not the entitlement itself; losing a row
/// here must not cost RevenueCat a 2xx and earn a retry that rewrites a profile we already got
/// right. `event_id` is unique, so a redelivery conflicts — which is success, not an error.
async function recordEvent(
  // deno-lint-ignore no-explicit-any
  serviceClient: any,
  profileId: string,
  eventId: string | null,
  eventType: string,
  tier: string | null,
  outcome: ApplyOutcome,
  stateAsOfMs: number | null,
): Promise<void> {
  const { error } = await serviceClient.from("subscription_events").insert({
    profile_id: profileId,
    event_id: eventId,
    event_type: eventType,
    tier,
    outcome,
    state_as_of: stateAsOfMs === null ? null : new Date(stateAsOfMs).toISOString(),
  });
  // 23505 is the redelivery case and is expected; anything else is logged and swallowed.
  if (error && error.code !== "23505") {
    console.error(`[revenuecat-webhook] could not record provenance: ${error.message}`);
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const expectedSecret = Deno.env.get("REVENUECAT_WEBHOOK_SECRET");
  const presented = req.headers.get("Authorization");
  if (!expectedSecret || !presented || !(await timingSafeEqual(presented, expectedSecret))) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  const apiKey = Deno.env.get("REVENUECAT_REST_API_KEY");
  if (!apiKey) {
    // Deployed without its key. 500 rather than a silent ack, so RevenueCat keeps the events queued
    // for redelivery instead of us dropping real purchases on the floor while the secret is missing.
    console.error("[revenuecat-webhook] REVENUECAT_REST_API_KEY is not set");
    return jsonResponse({ error: "Not configured" }, 500);
  }

  let payload: WebhookPayload;
  try {
    payload = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  // Tolerates the event being the whole body rather than nested under `event`, in case the envelope
  // documented above isn't what actually arrives.
  const event: WebhookEvent = (payload?.event && typeof payload.event === "object")
    ? payload.event
    : (payload as WebhookEvent);
  const eventType = typeof event?.type === "string" ? event.type : "unknown";
  // RevenueCat's own event id, used to dedupe redeliveries in `subscription_events`. Null when the
  // payload carries none, which the ledger's partial unique index tolerates.
  const eventId = typeof event?.id === "string" && event.id.length > 0 ? event.id : null;

  const userIds = collectCandidateUserIds(event ?? {});
  if (userIds.length === 0) {
    // Anonymous-only delivery ($RCAnonymousID:... with no aliased UUID yet), or an event shape with
    // no identifier at all. 200 so RevenueCat stops: there is nothing here a retry would improve,
    // and the app re-syncs anyway the moment `logIn` aliases the anonymous id to a real one.
    console.log(`[revenuecat-webhook] ${eventType}: no resolvable Supabase user id, no-op`);
    return jsonResponse({ ok: true, handled: 0 });
  }

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const outcomes: Record<string, number> = {};
  for (const userId of userIds) {
    let state: SubscriberState | null;
    let outcome: ApplyOutcome | "unknown_subscriber";
    try {
      state = await fetchSubscriberState(userId, apiKey);
      outcome = state === null ? "unknown_subscriber" : await applyState(serviceClient, userId, state);
    } catch (err) {
      // RevenueCat unreachable, or the write failed — genuinely transient, and the entitlement is
      // now unrecorded. 5xx so RevenueCat redelivers; the whole handler is idempotent, so
      // reprocessing the ids that already succeeded costs nothing but a repeated read.
      //
      // Deliberately no payload, secret, key or purchase detail in this line — the error message is
      // ours, and the id is omitted rather than logged.
      console.error(`[revenuecat-webhook] ${eventType}: sync failed:`, (err as Error).message);
      return jsonResponse({ error: "Temporary failure, retry" }, 503);
    }
    outcomes[outcome] = (outcomes[outcome] ?? 0) + 1;

    // Provenance. Not recorded for `unknown_subscriber`: RevenueCat has never heard of that id, so
    // there is no decision to attribute and no profile the row would describe.
    if (outcome !== "unknown_subscriber") {
      await recordEvent(
        serviceClient,
        userId,
        eventId,
        eventType,
        state?.tier ?? null,
        outcome,
        state?.asOfMs ?? null,
      );
    }
  }

  // Event type and per-outcome counts only. No ids, no tiers, no products, no prices — enough to
  // tell "webhooks are arriving and matching profiles" from "webhooks are arriving and matching
  // nothing", which is the whole of what this log needs to answer.
  console.log(`[revenuecat-webhook] ${eventType}:`, JSON.stringify(outcomes));
  return jsonResponse({ ok: true, handled: userIds.length });
});

/* To invoke locally:

  1. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  2. Set the two secrets in supabase/functions/.env (REVENUECAT_WEBHOOK_SECRET,
     REVENUECAT_REST_API_KEY), then `supabase functions serve revenuecat-webhook --env-file
     supabase/functions/.env`
  3. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/revenuecat-webhook' \
    --header 'Authorization: <REVENUECAT_WEBHOOK_SECRET>' \
    --header 'Content-Type: application/json' \
    --data '{"api_version":"1.0","event":{"type":"INITIAL_PURCHASE","app_user_id":"00000000-0000-0000-0000-000000000000"}}'

*/
