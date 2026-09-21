// The two spellings of one subscriber, and why they cannot be collapsed.
//
// RevenueCat's app_user_id is case-sensitive. Swift's `UUID.uuidString` is uppercase and that is
// what `Purchases.logIn` is given, so RevenueCat holds the customer under the uppercase id.
// Postgres holds uuids lowercase.
//
// The webhook used to lowercase once, up front, and use that single value for both — ask
// RevenueCat about `f3318dc2-…` when it holds `F3318DC2-…`. That does not error. The endpoint
// creates the id it was asked about and returns an empty subscriber, which the webhook then
// correctly refuses to write `inactive` from. So every purchase logged "unknown_subscriber",
// wrote nothing, and read as a RevenueCat problem — for three pairs of testers and every real
// account, until a log line gave it away.
//
// The first test is the one that would have caught it.

import { assertEquals } from "jsr:@std/assert@1";
import { collectCandidateUserIds, normalizeUserId } from "./ids.ts";

const UPPER = "F3318DC2-1D68-403A-B66F-13E11FD1DEB7";
const LOWER = "f3318dc2-1d68-403a-b66f-13e11fd1deb7";

Deno.test("the id RevenueCat is asked about keeps the casing it arrived with", () => {
  const [candidate] = collectCandidateUserIds({ app_user_id: UPPER });
  assertEquals(candidate.revenueCat, UPPER, "asking under any other spelling finds nobody");
});

Deno.test("and the id Postgres is given is lowercased", () => {
  const [candidate] = collectCandidateUserIds({ app_user_id: UPPER });
  assertEquals(candidate.database, LOWER);
});

Deno.test("a lowercase event is left lowercase for both", () => {
  // Whatever arrived is what RevenueCat stores, so it is also what to ask about.
  const [candidate] = collectCandidateUserIds({ app_user_id: LOWER });
  assertEquals(candidate.revenueCat, LOWER);
  assertEquals(candidate.database, LOWER);
});

Deno.test("two spellings of one uuid are one subscriber", () => {
  const candidates = collectCandidateUserIds({ app_user_id: UPPER, aliases: [LOWER] });
  assertEquals(candidates.length, 1);
  // First seen wins, which is the id the event was addressed to.
  assertEquals(candidates[0].revenueCat, UPPER);
});

Deno.test("an anonymous id names nobody", () => {
  // The rule falls out of the uuid test rather than needing its own check — and a purchase made
  // before sign-in arrives exactly like this, with the real id following in `aliases`.
  assertEquals(normalizeUserId("$RCAnonymousID:904732bfcccc415abcedd83360ec1bcd"), null);
  assertEquals(collectCandidateUserIds({ app_user_id: "$RCAnonymousID:abc", aliases: [UPPER] }).length, 1);
});

Deno.test("both sides of a transfer are collected", () => {
  // Syncing only one leaves the other showing a subscription it no longer has.
  const other = "AAAAAAAA-1111-4111-8111-111111111111";
  const candidates = collectCandidateUserIds({ transferred_from: [UPPER], transferred_to: [other] });
  assertEquals(candidates.length, 2);
  assertEquals(candidates.map((c) => c.database).sort(), [other.toLowerCase(), LOWER].sort());
});

Deno.test("anything that is not a uuid is ignored rather than queried", () => {
  assertEquals(normalizeUserId("not-a-uuid"), null);
  assertEquals(normalizeUserId(""), null);
  assertEquals(normalizeUserId(undefined), null);
  assertEquals(collectCandidateUserIds({}), []);
});

Deno.test("surrounding whitespace does not create a second subscriber", () => {
  const candidates = collectCandidateUserIds({ app_user_id: `  ${UPPER}  `, aliases: [UPPER] });
  assertEquals(candidates.length, 1);
  assertEquals(candidates[0].revenueCat, UPPER);
});
