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

---

# Round 2 — client, website and untrusted input (2026-09-21)

Sweep of the web admin console, on-device persistence, and every path by which input enters the
iOS app from outside its own UI.

## Verified by me

### 4. HIGH — a shared flight email survives an account switch and is offered to the next account

`Twofold/Twofold/Shared/PendingFlightShare.swift:36-61`, `Twofold/Twofold/App/AppModel.swift:917-940`

`PendingShareStore` has `all()`, `add()`, `remove(id:)` and `save()` and **no `clear()`** — the only
store of the sixteen without one. `clearLocalSessionState()` names twelve stores and does not name
it. `HomeView.swift:464` reads `PendingShareStore.all()` with no user id anywhere in the record or
the read, from `.onAppear`, from `scenePhase == .active`, and from pull-to-refresh.

The payload is content, not a pointer: `subject`, `bodyText` (the whole email) and `pdfText`
(scraped from an attached boarding pass). A booking confirmation carries a legal name, booking
reference, ticket number, seat and itinerary.

So: A shares a flight email and never taps the card; A signs out or deletes their account; B signs
in and is shown "1 flight email to review", opens A's email, and can add the flight to B's couple.
This is the `PendingTripStore` bug that `PendingDraftStoreClearTests` was written about,
reintroduced on a store that holds a third party's data.

Fix: add `clear()`, call it beside `PendingTripStore.clear()`, add the test. Then fix the reason it
happened — nothing asserts that a store is reachable from the clearing path, so the sixteenth store
being forgotten is green. Extract the disk half of `clearLocalSessionState()` (no RevenueCat, which
is why the existing tests only cover the in-memory half) and assert every store is empty after it.

### 5. SAFE — the web admin console gate holds

Recording this so nobody re-reviews it. `site/src/app/(console)/layout.tsx:34-46` is an async server
component on the route **group**: `auth.getUser()`, then `isConsoleAdmin()`, then redirect. Every
page under `(console)` inherits it, there is no second layout that could shadow it, and
`isConsoleAdmin` returns false on any RPC error. There is **no service-role key anywhere in
`site/`** — verified by grep across `src/` and `scripts/`. Client-side `useAdminRoles` only filters
the nav tabs; forging it reveals a link that then hits the server gate and the RPC gate.

## Reported, production code, not independently reproduced

- **HIGH — `/api/support` is an unauthenticated mail relay.** No rate limit, no CAPTCHA, no proof of
  address control; only a honeypot. Each POST sends mail from our domain to an attacker-chosen
  address containing up to 5000 attacker-written characters. The RPC error is swallowed and the mail
  sent regardless, so any throttle added to `submit_support_request` would not help. Burns the same
  Zoho quota and domain reputation that `/api/waitlist` and the iOS help path depend on.
- **HIGH — nothing on disk sets a file protection class.** No `NSFileProtection*`, no
  `.completeFileProtection`, no data-protection entitlement anywhere in the repo, so everything
  inherits `CompleteUntilFirstUserAuthentication`. Trips, flights, memories and their notes, both
  home cities, the daily question text, pending memory photo bytes and the game catalogue are all in
  Application Support and therefore in an unencrypted iTunes/Finder backup, in plaintext, with no
  passcode needed. The main-app-only stores can take `.completeFileProtection`; `WidgetImageCache`
  cannot, because a Lock Screen widget must render — worth a comment saying so.
- **HIGH — App Lock is bypassable by a widget or notification tap.** `AppLockView` is a ZStack
  sibling with `zIndex(1)` (`RootView.swift:411`), but every sheet and cover is attached to the
  `Group` beneath it, and UIKit presents those over the window — above the lock. Neither `onOpenURL`
  (`:291`) nor `consumePendingRoute()` (`:479`) checks `appLock.isLocked`. `twofold://partner-drawing-pad`
  needs no id at all. `AppLockView`'s own comment calls itself "the full-screen cover RootView shows
  in front of everything else"; it is neither. **Both agents found this independently.** Needs
  fifteen minutes on a device before acting — it is read from SwiftUI presentation semantics, not
  observed.
- **MEDIUM-HIGH — content is in the app-switcher snapshot.** `appLock.lock()` fires on `.background`
  (`RootView.swift:196`) and iOS captures the snapshot during `.inactive`, one phase earlier.
  `PrivacyCoverView` is an `.overlay`, so it has the same modal-layering problem as the lock.
- **MEDIUM — the Supabase refresh token is `kSecAttrAccessibleAfterFirstUnlock`**, not
  `…ThisDeviceOnly` (supabase-swift 2.50.0 `Keychain.swift:86`, not configurable through
  `SupabaseClientOptions`). It is therefore included in an encrypted backup and restores onto a
  different device: the backup password, not the phone passcode, yields a live session. Fix by
  supplying a custom `AuthLocalStorage`.
- **MEDIUM — export artefacts are never deleted.** `CoupleDataExporter` writes an unzipped copy of
  the entire relationship — every CSV plus every memory photo downloaded in full — to `tmp`, then a
  zip beside it, and nothing removes either. Survives sign-out and account deletion. `Our Story.rtf`
  and `Our Story.pdf` are at fixed `tmp` paths with photos embedded, also never cleaned. Filenames
  are derived from the partner's name.
- **MEDIUM — `OfflineGameStateCache.record()` merges from an unscoped `read()`** and stamps the
  result with the *current* user id, so account A's daily question, session id and deck progress can
  be laundered into account B's snapshot and pass B's scope check. Every other cache fails closed;
  this one fails open. Fix: merge only when `existing.userID == userID`.
- **MEDIUM — the two pending stores carry no user id at rest**, so clearing on sign-out is the only
  defence — and `signOut()` does two network round trips before the clear. Force-quitting a
  seemingly-frozen sign-out leaves every cache intact, and `restorePendingMemoriesFromDisk()` then
  replays A's drafts into B's couple.
- **MEDIUM — one tap pairs you with a stranger.** A deep-linked invite prefills
  `RedeemPartnerCodeView`, which sends `origin: .link`, and `redeem_invite_code` auto-accepts a link
  origin with no inviter approval. The onboarding route for the same link resolves and shows the
  inviter's name and avatar first; the signed-in route resolves the same information only *after*
  redemption, to word the confirmation. Two routes to one irreversible action, one of which tells
  you who you are pairing with.
- **MEDIUM — `connection_accepted` never notifies on the auto-accept path.** The redeemer calls it,
  but `notify-connection-request` builds `expectedMatch` assuming the caller is the inviter, so the
  match inverts, the function 403s, and the client discards the error. Migration 20261008000000
  justifies unsupervised link pairing partly on "the inviter is told". They are not told. Same
  assumption breaks accept-notification when an accept restores a dissolved archive with reversed
  partner ordering.
- **LOW — attacker-controlled text in a system alert.** `twofold://reset-password?error_description=…`
  surfaces the attacker's sentence verbatim in the "Link expired" alert. Any installed app can fire
  it. No tappable link (`Text` takes the non-markdown overload), so it is phishing copy, not a click.
- **LOW — `twofold://invite/CODE` is dead.** `InviteCode.code(from:)` requires `invite` in
  `pathComponents`, but for that URL `invite` is the *host*, so the `url.host == "invite"` branch is
  unreachable and the file header's backward-compatibility promise is not kept. Also
  `twofold://<anyhost>/invite` returns the code `"INVITE"` and is matched before widget routing. The
  function has zero test coverage.
- **LOW — unescaped `preheader` in two email templates.** `renderTemplate` requires callers to
  pre-escape; every other token on the call is escaped and this one is not, in both
  `/api/support:140` and `/api/waitlist:85`. `EMAIL_RE` permits `<` and `>`. HTML injection into an
  internal alert an admin reads. Not header injection — whitespace is excluded and values are
  trimmed.
- **LOW — `widgetSnapshot.v1`…`v4` are orphaned forever.** `clear()` removes only `v5`. Up to four
  stale blobs with the then-current account's names, cities, anniversary, next reunion, couple and
  partner ids, and in v3-and-earlier the public drawing-pad URLs, in the backed-up app-group root.
- **LOW — App Lock does not cover the widgets.** "Require Face ID" still leaves the partner's name,
  face, city, distance, next reunion and latest memory photo on the Home Screen, three of them on
  the Lock Screen. Inherent to widgets; the Settings copy implies otherwise. A product decision.
- **LOW — waitlist membership is enumerable** (409 vs 200, unauthenticated, unthrottled), and each
  miss enrols and emails the address probed.
- **LOW — no security response headers at all.** No CSP, no `frame-ancestors`, no `Referrer-Policy`.
  Supabase SSR auth cookies are necessarily `httpOnly: false` because the browser client reads them,
  so any XSS is full session theft including an admin's. No XSS sink found today — zero
  `dangerouslySetInnerHTML` in `site/src`.
- **LOW — `revoke … from anon` on the new admin functions does not hold**, the same
  default-privileges mechanism as item 1's neighbours. Defence-in-depth only: every one of them
  checks `is_support_admin()` / `is_billing_admin()` as its first statement, verified.
- **LOW — `x-pathname` is set on the response, not forwarded on the request**, so the console
  layout's `headers().get("x-pathname")` is always null and the bookmark-preserving redirect never
  works. What *does* reach it is a client-supplied `X-Pathname` header. No open redirect today —
  `encodeURIComponent` plus the callback's `/^\/(?!\/)/` validation stand in the way — but that
  regex is the only thing standing there.
- **LOW — share extension reads an unbounded host-supplied URL** into memory before checking the
  size cap, and will fetch an `http(s)` URL if the host app supplies one.
- **LOW — `[weather]` logs a home city** to the unified log on a failure path
  (`WeatherService.swift:63`). The only other three log sites are clean.

## Verified safe in round 2

- Recovery links cannot establish or hijack a session: the SDK defaults to PKCE, so a crafted
  `#access_token=` throws and a crafted `?code=` fails without the local verifier. **Latent:**
  setting `flowType: .implicit` would silently turn this into one-link account takeover. Worth a
  comment at the call site.
- Push payloads cannot reach a UI string, a URL or an arbitrary navigation target — the parser
  accepts only `UUID(uuidString:)` and fixed enum raw values, and `.flight(id)` resolves locally.
- No deep link reaches a destructive action. No unpair, delete, purge or export route exists.
- The share extension holds no credentials and shares no session; the App Group holds no tokens.
- Google's callback is handled before the app's own parsers, which would reject it anyway on scheme.
- Export scoping after a split is correct by design: reads stay open so a dissolved couple can still
  export, writes are shut by `is_couple_active`, so there is no "after the split" data to leak.
- Fifteen of sixteen stores are correctly registered in the clearing path, and every `restore(for:)`
  is called with a real user id; a nil id fails the `guard let` rather than falling through.
- Account deletion runs the identical clearing path and signs out of Supabase, so a device is not
  left silently signed in to a deleted account.
- All twenty-two feedback-board policies scope writes to `user_id = auth.uid()`. The one policy that
  looks wrong (`feature_requests_update_own_recent`) is covered by a BEFORE UPDATE trigger.
- No Sanity write token in any client path; the one Studio tool that writes to Supabase is gated by
  `is_feedback_admin()` rather than by Studio's own auth.
- Both destructive edge functions (`admin-actions`, `send-support-reply`) verify the caller with the
  caller's own JWT before constructing a service client.

## Still unreviewed

- `ingest-support-email` / `send-support-reply` / the support-reply migrations — a live untrusted
  input path into admin-facing UI, reachable by Zoho without a Supabase JWT. Untracked and being
  written while this sweep ran, so deliberately skipped.
- `PricingClient.tsx` — passes the Supabase user id to RevenueCat Web Billing and reads entitlement
  back client-side. Whether any server trusts a client-asserted entitlement was not answered.
- `Twofold.entitlements` has `aps-environment: development`. Distribution signing normally rewrites
  it; worth a glance before the next App Store build.

---

# Round 3 — data at rest and encryption (2026-09-21)

Commissioned specifically to settle file protection and encryption of user-provided data. It
turned up something larger on the way.

## Verified by me

### 6. HIGH — deleting an account leaves every photograph in R2, permanently, and the privacy policy says otherwise

Verified: `delete-account/index.ts` contains **zero** references to R2. `purge_couple_data`
(`20260901001900:35-39`) and `private.scrub_account` (`20261109000900:177-178`) delete rows from
`storage.objects` — the *Supabase Storage* index — and then `delete from public.couples`. Neither
touches R2, which is where the objects have actually lived since the migration. The only
server-side R2 deletes in the repo are in `purge-support-attachments`. The only R2 deletes for
couple content are client-side, for individually deleted memory photos and flight documents
(`BackendService.swift:2756, 3269, 3278`) — not for deletion of the account.

So after `delete-account` returns `{ok: true}`: `avatars/{uid}/…`, `drawing-pads/{coupleID}/…`
remain. After the 90-day archive purge: every `memory-photos/{coupleID}/…` and
`flight-documents/{coupleID}/…` remains — the couple's photographs and their boarding passes.

**It gets worse, and this is the part that sets the deadline.** `purge_couple_data` cascades
`memory_photos` and `flight_documents` away, and those tables are where the object paths live.
`scripts/delete-r2-objects.ts` takes keys rather than prefixes precisely because "every path is
already recorded in the database". `_shared/r2.ts` has no list-objects call. So once the purge has
run for a couple, **there is no longer any way to determine which objects were theirs.** This is
not a missing delete call; it is a state that cannot be recovered from without a bucket listing no
code here can perform.

Not an access-control hole — the bytes are unreachable through the app, since
`can_access_storage_object` needs an `auth.uid()` and a deleted account can never sign in. It is an
unbounded-retention and right-to-erasure failure, and it contradicts three shipped statements:

- privacy policy: "Your own uploads (your profile photo, your drawings) … are deleted."
- privacy policy: "Anything you delete goes from Twofold immediately … for up to 7 days … and no
  longer."
- FAQ, in-product (`20261021000000`, `20261027000000`): "permanently deleted for both of you once
  it runs out."

The fix already has a pattern in the repo: `purge-support-attachments` pairs an RPC that returns
keys with an edge function that deletes them. `purge_couple_data` and `scrub_account` need the
same — return the paths before the cascade eats them. **Do this before more couples pass 90 days.**

### 7. MEDIUM-HIGH — the Supabase Storage originals are orphaned too

Nine call sites switch off `storage.protect_delete()` with
`set_config('storage.allow_delete_query', 'true', true)` and delete rows directly. That trigger
exists to prevent exactly this: its own hint reads "This prevents accidental data loss from
orphaned objects." Deleting the row strands the file, because `storage.objects.version` is what
maps a row to its backing key. Reported as verified on the local stack: **0 rows in
`storage.objects`, 7 objects still in the storage backend.** So every deletion since September has
orphaned the originals the R2 soak period is preserving. Not reproduced by me, and not proven
against hosted S3.

Related, LOW: the four legacy buckets are still *writable*, not just readable. The soak needs only
reads, so dropping the INSERT/UPDATE policies costs nothing and closes both free hosting under a
user's own prefix and a `::uuid` cast issue in the drawing-pads policies.

## The data-at-rest plan (the thing this round was for)

A complete inventory of every persistence site is in the round-3 agent report; the decisions are
below. The short version: **per-write protection classes plus a one-time migration. Not the
entitlement, and mostly not application-level encryption.**

### What may be raised, and what may not

Proven from the code: **nothing in the main app runs while the device is locked.** No
`BGTaskScheduler`, no `BGAppRefreshTask`, no background `URLSession`, no `beginBackgroundTask`
anywhere. `UIBackgroundModes` declares `remote-notification` but
`didReceiveRemoteNotification:fetchCompletionHandler:` is not implemented, so the app is never
woken to do disk work. `WidgetSnapshotWriter.refresh` is foreground-only.

Equally proven: **the widget extension does read the App Group while locked.** The Live Activity's
Lock Screen view reads the airline logo (`JourneyLockScreenView.swift:105`), five widgets declare
Lock Screen accessory families and their providers all call `WidgetSnapshot.read()`, and
`DrawingPadWidget.swift:58-59` *writes* into the container from `getTimeline`.

| What | Class | Why |
|---|---|---|
| App Group images + the group plist | `.completeUntilFirstUserAuthentication`, set explicitly | Locked readers proven. `.complete` blanks the widgets, and the writes are `try?` so nothing would log it |
| `OfflineDataCache`, `OfflineGameStateCache`, `GameContent`, `PendingMemories`, `PendingTrips` | `.completeFileProtection` | Read only on the main app's launch path, which is after an unlock by definition |
| `Caches/MemoryPhotos` (up to 250 MB of photographs), `Caches/RemoteImages` | `.completeFileProtection` | Foreground readers only. Widgets read their own separate copies |
| `tmp` exports | `.completeFileProtection` | Switch these four to `.completeUnlessOpen` only if a real report comes in of a share failing after a screen lock |
| PostHog / RevenueCat directories | leave alone | Third-party owned; PostHog flushes from the background |

Directories need the class set separately — `setAttributes` does not recurse, and a file created
in a CUFUA directory inherits CUFUA. Set both.

### Migration is required and is the easy half to forget

Setting the option changes nothing already on disk. A six-month-old install keeps its 250 MB photo
cache at CUFUA forever, because `MemoryPhotoDiskCache.write` only runs for photos `has(path:)`
reports missing. Use `FileManager.setAttributes(.protectionKey:)` over the existing trees — it
rewraps the per-file key without touching bytes, so it is fast — walking with
`FileManager.enumerator`. Guard on `UIApplication.isProtectedDataAvailable`: raising CUFUA to
Complete needs the class-A key, which does not exist while locked, so a locked run fails every file
and must not stamp its version. Retry on `protectedDataDidBecomeAvailableNotification`.

### Do NOT use `com.apple.developer.default-data-protection`

It would classify the files the main app writes into the App Group at Complete, and the widget
would draw blank avatars and a missing airline logo on every locked render. The writes are `try?`,
so the first report would come from the App Store. A per-write option at the call site is also
legible to a reviewer against the actual readers, which an entitlement in a plist is not.

### Is file protection enough? Mostly yes — four places it is not

1. **No device passcode: protection is void.** Class keys are derived without a user secret, so
   `.completeFileProtection` degrades silently to nothing. Application-level encryption does not
   fix this either, because a Keychain key degrades the same way. `AppLockService.swift:37-39`
   already computes this exact condition and uses it only to grey out a toggle — **the app knows
   its encryption is void and does not say so.** The correct response is one line of Settings copy,
   not crypto.
2. **Backups ignore protection classes entirely.** A Complete file is backed up like any other, so
   `PendingMemories` photo bytes, `OfflineDataCache` and the group plist are all in every backup.
   The lever here is `isExcludedFromBackup`, which should go on the derivable stores
   (`OfflineDataCache`, `OfflineGameStateCache`, `GameContent`, the App Group images) and must NOT
   go on `PendingMemories`/`PendingTrips`, which are the only copy.
3. **The Supabase refresh token is backup-eligible.** supabase-swift 2.50.0 writes it at
   `kSecAttrAccessibleAfterFirstUnlock`, not `…ThisDeviceOnly`, so an unencrypted backup restored
   onto a second device carries a live session. Fix with a custom `AuthLocalStorage`. **Migration
   matters:** read the existing item at the old accessibility and rewrite it, or every signed-in
   user is silently signed out on update.
4. **Two sensitive stores are pinned in plists you do not own.** `pendingFlightShares` (a whole
   booking email) shares the group plist with the widget snapshot, and `pendingGameResponses` (free
   text answers to intimate questions) is in `UserDefaults.standard`. Neither can take a class or a
   backup exclusion. The fix is not encryption — it is moving both into files the app owns, which
   then gives both for free.

**Application-level encryption is not warranted anywhere else, and I would not add it.** For the
widget snapshot specifically it buys nothing: the widget must decrypt while locked, so the key
would sit at `AfterFirstUnlock` in a shared Keychain group — the same unlock semantics as CUFUA —
and it would cost a new entitlement on two targets plus a key-provisioning race.

**Testing note:** the simulator does not implement data protection; every file reports
`NSFileProtectionNone`. A unit test asserting a protection class **passes vacuously there and
proves nothing.** Assert at the call site, or test on hardware.

## Third parties and database, from the same round

- **MEDIUM — OpenAI retains the flight-email prompts.** `parse-flight-email` sends the email subject
  and body, and on fallback the whole scraped PDF text — passenger name, PNR, ticket number, seat,
  itinerary — with no redaction. Good news: no `user` field, no metadata, nothing ties it to an
  account, and the privacy policy discloses it accurately. But `store` is not set and defaults to
  true on the Responses API, so the prompts sit in the organisation's Logs dashboard for 30 days.
  `store: false` is a one-line fix. Confirm the default against current OpenAI docs first.
- **MEDIUM — the privacy policy says support content "isn't stored in the Twofold database".** That
  stopped being true with `20261109001100`. `support_requests` holds email, name, subject and
  message, and `profile_id` deliberately has no FK so "the record has to outlive the account" — so a
  "please delete my account" ticket survives the deletion it requested. Either the copy or the
  retention needs a decision.
- **LOW-MEDIUM — RevenueCat receives the account email**, by a comment's own admission "purely so a
  person is findable in that dashboard", and this is not disclosed where OpenAI and PostHog are.
  Account deletion also never deletes the RevenueCat customer, so the email and UUID survive there.
- **LOW — `partner_subscription_lapse_partner_name` survives a scrub.** `leave_couple` copies the
  leaver's first name onto the remaining partner's row and `scrub_account` does not null it, so a
  third party's name persists on a "Deleted User" row against the policy's "partner nickname … are
  erased".
- **LOW — `public.places` is globally readable** (`USING (true)` for authenticated) with no owner
  column. A typed address or dropped pin on a memory writes exact coordinates and the typed name, so
  any signed-in user can read the addresses Twofold users have tagged memories at. Unattributable —
  no owner column, and `memories` is RLS'd — which is why this is low. The common path is safe:
  current-location defaults go through `HomeLocationService`, which coarsens.
- **LOW — `/api/waitlist:105` logs a nodemailer rejection**, whose envelope contains the signup's
  email address, into Vercel logs.

**Encryption at the database layer: argued and rejected.** It buys only "the operator cannot read
it", and costs query, sort, index, export and support — with a key that, for a two-device shared
app with full multi-device restore, must live on a server we control. The threat is already
answered structurally: the support console is content-blind by construction
(`20261109000800:21-22`, verified to return only `count(*)` for memories and trips), `private` is
unreachable, RLS is on all 53 tables. Supabase at-rest encryption plus RLS plus a content-blind
admin surface is the right answer here.

## Verified correctly protected in round 3

- R2 encrypts every object with AES-256 automatically and cannot be turned off, so no code path can
  write an unencrypted object and there is nothing to configure.
- The other 14 `storage.objects` policies all reference `auth.uid()` or `is_couple_member`
  correctly, including the deliberate asymmetry that lets a dissolved couple still read and export.
- PostHog carries no user content — all 24 `capture` call sites read, every property a count, bool,
  enum or uuid. Session replay and screen-view capture are both off.
- AeroAPI and the community trackers receive a flight identifier and nothing else. Sanity receives
  no user data at all. Both match the policy.
- Edge-function and Postgres logging carry no user-written content anywhere — 168 `console.*` calls
  and every `raise` in 286 migrations checked. There is no Sentry or Crashlytics in the project.
- Support tables have RLS on with zero policies: deny-all, service-role only.
- Support attachment keys are minted server-side, never caller-chosen.
