//
//  ids.ts
//  revenuecat-webhook
//
//  Which subscriber an event is about, in the two spellings the two systems use.
//
//  Extracted from index.ts so it can be tested. It is worth testing: collapsing these two
//  spellings into one broke every purchase in the product, silently, and the only symptom was a
//  log line saying RevenueCat had never heard of a user it had heard of perfectly well.
//

/// The fields of a RevenueCat webhook event that can name a subscriber.
export interface IdentifyingEvent {
  app_user_id?: string;
  original_app_user_id?: string;
  aliases?: unknown;
  transferred_from?: unknown;
  transferred_to?: unknown;
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/// One subscriber, in the two spellings the two systems use.
///
/// This distinction is the whole point, and collapsing it is what broke every purchase for weeks.
/// Swift's `UUID.uuidString` uppercases, and that is exactly what is passed to
/// `Purchases.shared.logIn` — so RevenueCat stores the customer under the UPPERCASE id, and
/// **RevenueCat's app_user_id is case-sensitive**. Postgres stores uuids lowercase.
///
/// The original version lowercased once, up front, with a comment explaining the uppercase/
/// lowercase split — and then used that one lowercased value for both. Asking RevenueCat about
/// `f3318dc2-…` when it holds `F3318DC2-…` does not error: the endpoint creates the id it was
/// asked about and hands back an empty subscriber. Which `isBlankSubscriber` then correctly
/// declines to write `inactive` from, because a blank record is not evidence of no subscription.
/// So every INITIAL_PURCHASE logged "unknown_subscriber", wrote nothing, and looked like a
/// RevenueCat problem.
export interface CandidateId {
  /// Exactly as it arrived. RevenueCat echoes back the id it stores, so whatever spelling turned
  /// up is by definition the one to ask about.
  revenueCat: string;
  /// Lowercased, for the `profiles` row.
  database: string;
}

export function normalizeUserId(value: unknown): CandidateId | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  const lowered = trimmed.toLowerCase();
  return UUID_PATTERN.test(lowered) ? { revenueCat: trimmed, database: lowered } : null;
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
export function collectCandidateUserIds(event: IdentifyingEvent): CandidateId[] {
  const raw: unknown[] = [event.app_user_id, event.original_app_user_id];
  for (const list of [event.aliases, event.transferred_from, event.transferred_to]) {
    if (Array.isArray(list)) raw.push(...list);
  }
  // Deduped on the lowercase form, because two spellings of one uuid are one subscriber — while
  // keeping the spelling that arrived, which is the one RevenueCat answers to.
  const byDatabaseId = new Map<string, CandidateId>();
  for (const value of raw) {
    const id = normalizeUserId(value);
    if (id && !byDatabaseId.has(id.database)) byDatabaseId.set(id.database, id);
  }
  return [...byDatabaseId.values()];
}

