# Security backlog

Findings from the endpoint sweep on 2026-09-21. Nothing here is fixed. Ordered by what I would
do first, not by discovery order.

Each entry says how far verification actually got, because "an agent said so" and "I reproduced
it" are different things and the gap matters when you come back to this cold.

## Verified against production or a live database

### 1. CRITICAL — any signed-in user can reset every rate limit

`supabase/migrations/20260918000000_per_user_rate_limits.sql:137`

`consume_rate_limit` purges the caller's ledger using a caller-supplied `p_window`, and the guard
only rejects `<= 0` and `> 1 day`. A tiny *positive* window makes the purge cutoff `now() - 1µs`,
which is every row the caller has written in that bucket. The function is granted to
`authenticated`, so it is reachable over PostgREST with the anon key that ships in the app binary
— no edge function involved.

Reproduced locally in a rolled-back transaction with back-dated rows (a single transaction cannot
show this, because `now()` is frozen inside one):

```
limit 3/hour, 4th call              allowed=f  retry_after=3300
BYPASS: same RPC, 1 microsecond     allowed=t             ledger 3 rows -> 1
the 1-hour limit again              allowed=t  retry_after=0
```

Removes the ceiling on everything metered: `parse-flight-email` (OpenAI), `resolve-flight`
(AeroAPI), `submit-help-message` (mail from our own authenticated Zoho mailbox, so domain
reputation), `sync-my-subscription`, `storage-url`.

The migration header argues the purge is safe because it "can only ever lower the count, and only
by rows the window predicate would have excluded anyway". That holds within one call and fails
across calls with different windows. `supabase/tests/rate_limit_test.sql:196` pins the negative
window and stops there.

Fix: delete the `bucket = p_bucket and occurred_at <= now() - p_window` arm and keep only
`occurred_at <= now() - c_max_window`. Retention stays bounded by the 1-day constant, which is
what the safety argument actually rests on, and nothing caller-supplied touches the cutoff. Do
not clamp `p_window` to a minimum — a caller would just pass the minimum. Add the missing
assertion next to the negative-window one.

### 2. MEDIUM — avatars in the private bucket are readable unauthenticated

`supabase/migrations/20260901001000_private_avatars_drawing_pads.sql:46`

`avatars_select_pending_inviter` applies to `PUBLIC`, and its `USING` clause never references
`auth.uid()` or the invite code — it requires only that the folder uuid belongs to somebody with
a pending, unexpired invite. `anon` holds SELECT on `storage.objects` (verified). The policy's own
comment justifies it as "anyone who knows a still-pending, unexpired invite **code**", which is
what `get_invite_code_inviter_info(p_code)` does; this policy gates on knowing the inviter's
profile uuid instead. Implementation and stated intent differ, which reads as an oversight rather
than an accepted risk.

Note this guards the originals still in Supabase Storage from before the R2 migration — the ones
awaiting the soak-period deletion. Deleting those closes it as a side effect.

### 3. LOW — two anon-callable RPCs with no caller check

Both return HTTP 200 to the published anon key against production:

- `is_support_admin(check_id uuid)` -> `false`. The `DEFAULT auth.uid()` path used internally is
  correct; the exposure is that the parameter is reachable, so anyone can ask whether a given uuid
  is an admin and which role it holds. Same for `is_console_admin` / `is_billing_admin` /
  `is_feedback_admin`.
- `flights_used_this_month(p_couple_id uuid)` -> `0`. No membership check. Unlike
  `couple_is_subscribed` and `is_couple_active`, which keep their grant because RLS policies
  execute as the caller, this one is referenced by zero policies, so the grant buys nothing.

## Reported by review, not independently reproduced

All in production code. Listed with the reviewer's severity.

- **HIGH — SMTP command injection in `submit-help-message`.** `input.message` goes into the DATA
  section unescaped, and denomailer 1.6.0 does no dot-stuffing, so a `\r\n.\r\n` in the body
  terminates DATA early on an already-authenticated Zoho session. `subject` is protected by
  `singleLine`; the body deliberately is not, correctly, because it is multi-line. The injection
  primitive is confirmed against the real encoder; end-to-end delivery is not, since proving it
  means sending real mail. Fix by dot-stuffing the body, not by flattening it.
- **HIGH — R2 presigned PUT has no size bound.** `_shared/r2.ts` signs host and content-type and
  nothing else; there is no `content-length-range`. Supabase Storage enforced `file_size_limit =
  50MiB` (`config.toml:118`), so the R2 migration dropped that ceiling silently. `contentType` is
  also caller-supplied and unvalidated. Not stored XSS — no public R2 domain exists and
  `airline-logos/` is not writable by users — so this is storage and Class A operation cost.
- **MEDIUM-HIGH — `add-flight` has no rate limit at all.** Up to three billed AeroAPI calls per
  invocation, none cached, and the monthly allowance deliberately does not gate them (an
  over-allowance add still happens, just with `tracking_enabled = false`). `resolve-flight` got a
  40/hour bucket for exactly this reason and `add-flight` was left out. It also passes no `usage`
  context, so the spend records as `unattributed`.
- **MEDIUM — `notify-couple-event` delivers attacker-chosen text to a partner.** `detail` is
  unvalidated and uncapped and lands verbatim in the push body, and `game_reminder` is
  deliberately absent from `PREFERENCE_COLUMN` so it skips the preference check entirely. No rate
  limit. The recipient is correctly constrained to the caller's own partner, so this is a
  harassment vector inside a couple, not a way to reach strangers.
- **MEDIUM — `notify-connection-request` skips the 6-hour throttle.** The throttle lives in
  `send_connection_request_reminder`; calling the edge function directly bypasses the RPC and its
  ledger. The membership check is real, so the target is always someone with a genuine pending
  request. Body text includes the attacker's own `first_name`, which is self-updatable and
  unvalidated.
- **MEDIUM — `flights.trip_id` is validated nowhere.** No FK, no trigger, no policy.
  `add-flight:336` writes it with the service role, and `BackendService.swift` PATCHes it
  directly. Reachable consequence: `flight_documents_insert_members_active` checks
  `couple_is_subscribed` by joining the flight's *trip*, so a lapsed couple that can name a
  subscribed couple's trip uuid regains document uploads. Obtaining a foreign trip uuid is the
  hard part.
- **MEDIUM — `revenuecat-webhook` consumable grants trust body identifiers.** The entitlement path
  re-reads state from RevenueCat; the consumable path takes `app_user_id`, `product_id` and
  `transaction_id` from the POST body and grants credits, with idempotency keyed on the
  attacker-chosen `transaction_id`. Behind the shared secret, so not an unauthenticated bypass,
  but it is the one place in the file that departs from the read-back design its header spends
  thirty lines justifying.
- **LOW — `consume_rate_limit`'s own revoke did not hold.** `from public` only, the exact pattern
  `20261108000000` exists to fix. No impact today (it raises on a null `auth.uid()`), so
  defence-in-depth. Fold into the fix for item 1.
- **LOW — PostgREST filter injection in `add-flight`.** `.or(\`iata.eq.${originCode},...\`)` with
  `originCode` client-supplied on the `pending` path. supabase-js URL-encodes it so it cannot
  escape the parameter; blast radius is a wrong country/timezone on the attacker's own row.
- **LOW — `aeroapi-webhook` secret travels in the query string** and is echoed back in the
  `register=1` response body. Comparison is `!==`, not constant-time. Function is dormant.
- **LOW — `revenuecat-webhook` logs Supabase user UUIDs** at `:242` and `:267` while its own
  comments at `:434` and `:492` say ids are never logged.

## Not live — in the 17 migrations `twofold-47` had in flight on 2026-09-21

Found before shipping, which is the good case. Re-check these against whatever actually lands.

- `get_feedback_public_profiles(uuid[])` is anon-executable with no scoping, and returns name and
  avatar path for any profile id, bypassing `profiles` RLS. `feature_votes` and `feature_comments`
  both expose `user_id` under `using (true)`, which supplies the ids in bulk. Confirmed **404 in
  production**, so the chain is not live yet.
- `submit_support_request` is anon-callable directly, skipping every validation the Next route
  performs (honeypot, email regex, length caps, category whitelist) and every rate limit. Because
  `thread_key` is a pure function of subject and lowercased email, someone who knows a victim's
  address can inject rows into that victim's existing thread, and
  `admin_set_support_request_status` acts on the whole thread.
- `feedback_admins_select_own_or_admin` subqueries its own table and raises `infinite recursion`
  for every direct read. Fails closed, so not exploitable, and the app is unaffected because
  `my_admin_roles()` is SECURITY DEFINER. The tempting fix — a permissive policy — would open the
  admin list; call `is_console_admin()` instead.

## Verified safe, so nobody re-checks them

- `revenuecat-webhook` secret comparison is genuinely constant-time (SHA-256 both sides, then
  fixed-length compare). Method gate precedes it; no CORS/OPTIONS path around it.
- `storage-url` cross-couple reads are refused, each path checked individually, all-or-nothing
  refusal avoids an existence oracle, and passing the service-role key as `Authorization` fails
  twice over.
- SigV4 in `_shared/r2.ts` is correct: method, path and full query string are signed, so a GET URL
  cannot be replayed as PUT and the expiry cannot be extended. `MAX_EXPIRES_IN` is enforced first,
  in the only signing path. Signatures pinned against botocore.
- Path traversal is refused in `can_access_storage_object` and inert anyway, since the signature
  is over the unnormalised path.
- `airline-logo`'s outbound URL is not caller-influenced (`/^[A-Za-z0-9]{2,3}$/`).
- RLS is enabled on all 53 `public` tables. The 9 with no policies are deny-all, proven with a
  seeded row rather than an empty-table `DELETE 0`. No views exist in `public`, so that whole
  class of bypass is absent.
- No self-promotion to admin and no entitlement self-grant: `feedback_admins`,
  `streak_repair_credits` and `record_export_credits` are SELECT-policy-only and inserts are
  refused. Proven.
- The subscription-column guard covers all six columns including the newly added
  `subscription_store`.
- `private` schema is unreachable: no USAGE for anon or authenticated, and `config.toml` exposes
  only `public` and `graphql_public`.
- `play-chess-move` is the best-guarded function in the codebase — membership, status and turn all
  checked server-side, turn derived from a replay of the append-only log.
- `delete-account`, `sync-my-subscription`, `refresh-flight`, `register-live-activity-token`,
  `end-live-activity-token`, `resolve-flight`, `parse-flight-email` all take the acting id from
  `auth.getUser()` and re-verify entitlement before any service-role work.
- `notify-game-turn` is not reachable with a user JWT at all.

## Process notes

- One of the three reviewing agents read `consume_rate_limit`, cited the negative-window guard,
  and declared it well built. It is item 1. Two others reproduced the bypass. Treat single-agent
  "verified safe" claims about a security control as unverified.
- On 2026-09-21 the local database contained objects from migrations absent from
  `schema_migrations`, so `supabase db reset` and the running database had diverged and any pgTAP
  run was testing an unrecorded schema.
