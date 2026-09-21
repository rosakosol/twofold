# Security remediation plan

Companion to `security-backlog.md`, which holds the findings and the evidence. This holds the
order of work and what each change actually is.

Ordered by irreversibility first, then by exposure, then by cost. The first item is first because
it gets worse on its own; nothing else on this list does.

Effort is a rough half-day unit: **S** under an hour, **M** a few hours, **L** a day or more.

---

## Phase 0 — Losing ground daily

### 0.1 Delete R2 objects when an account or an archive is purged — **L**

**Why first.** `purge_couple_data` cascades `memory_photos` and `flight_documents` away, and those
tables hold the object paths. `_shared/r2.ts` has no list operation and `delete-r2-objects.ts`
takes keys because "every path is already recorded in the database". So every couple that passes
their 90 days becomes permanently unrecoverable — not "we still have to delete these", but "we can
no longer find out what to delete". Everything else on this list waits patiently; this does not.

**Change.** Follow the pattern already in the repo: `purge-support-attachments` pairs an RPC that
returns keys with an edge function that presigns a DELETE for each.

1. New migration: `private.couple_object_keys(p_couple_id uuid) returns setof text`, returning
   `memory_photos.photo_path`, `flight_documents.file_path`, and the derived `drawing-pads/…` and
   `avatars/…` paths. Service-role only, revoked `from public, anon, authenticated` — see 5.1 for
   why all three must be named.
2. Change `purge_couple_data` and `private.scrub_account` to collect those keys into a new
   `public.pending_object_deletions(key text, enqueued_at timestamptz)` table **before** the
   deletes that strand them. A table rather than an inline call because the RPC runs inside a
   transaction and an R2 round trip does not belong there.
3. New edge function `purge-r2-objects`, cron'd, draining that table with `presign(..., { method:
   "DELETE" })`. Delete the row only on a 2xx or a 404, so a transient failure retries and an
   already-gone object does not wedge the queue.
4. `delete-account` calls it inline for the caller's own avatar and drawing pad, so single-account
   deletion does not wait for cron.

**Risk.** This deletes user data irreversibly. Build it with the drain disabled, let the queue fill
for a day, inspect the keys against a couple you control, then enable. A bug here destroys
photographs belonging to people who did not ask for it — the opposite failure of the one being
fixed, and worse.

**Verify.** pgTAP: purging a couple enqueues exactly the keys that couple owned and nothing else.
A test with two couples, asserting the other's keys are absent, is the one that matters.

### 0.2 Decide the Supabase Storage originals — **S to decide, M to execute**

Nine call sites switch off `storage.protect_delete()` and delete rows directly, which strands the
backing file — the exact loss that trigger exists to prevent. So the originals the R2 soak is
preserving have been orphaning since September.

Two honest options, and the decision is yours:

- **End the soak.** Delete the four legacy buckets' contents **through the Storage API**, not by
  deleting rows. This is the simpler path and it retires 0.2 entirely.
- **Keep the soak.** Then at minimum drop the INSERT/UPDATE policies on all four buckets — reads
  are all a soak needs, and leaving writes open is free hosting under a user's own prefix, billed
  to us, with no MIME allowlist.

Either way, stop deleting rows directly: the remaining call sites should go through the Storage
API or stop pretending to delete anything.

---

## Phase 1 — Live, exploitable, and cheap to close

### 1.1 Rate limiter reset — **S**

`20260918000000_per_user_rate_limits.sql:137`. Reproduced: a 1-microsecond `p_window` purges the
caller's ledger and every limit resets.

Delete the `bucket = p_bucket and occurred_at <= now() - p_window` arm, keep only
`occurred_at <= now() - c_max_window`. Retention stays bounded by the 1-day constant, which is what
the header's safety argument actually rests on, and nothing caller-supplied touches the cutoff.

Do **not** clamp `p_window` to a minimum — a caller would pass the minimum.

Fold in the missing revoke while you are there: `from public, anon, authenticated`.

**Verify.** The assertion that is missing today, next to the negative-window one in
`rate_limit_test.sql`: exhaust a limit, back-date the rows, call with `interval '1 second'`, assert
the next 1-hour call is still refused. Confirm it fails before the fix.

### 1.2 `PendingShareStore` is never cleared — **S**

Add `clear()` to `PendingFlightShare.swift`, call it in `clearLocalSessionState()` beside
`PendingTripStore.clear()`.

Then fix the reason it happened, which is the more valuable half. Nothing asserts a store is
*reachable from* the clearing path, so the sixteenth store being forgotten is green. Extract the
disk/defaults half of `clearLocalSessionState()` into `clearPersistedAccountState()` — no
RevenueCat, no PostHog, no `UNUserNotificationCenter`, which is why the existing tests only cover
the in-memory half — and test it by dirtying every store and asserting each is empty.

**Verify.** The control that proves the test works: remove one `.clear()` line and watch that
store's assertion go red.

### 1.3 `avatars_select_pending_inviter` — **S**

The policy applies to `PUBLIC` and never references `auth.uid()` or the invite code, so anyone who
knows an inviter's profile uuid reads their avatar unauthenticated. Its comment claims it gates on
knowing the invite *code*; it does not.

Either add the caller check the comment describes, or drop the policy — the code-gated path is
`get_invite_code_inviter_info`, which already exists and already returns the avatar. Dropping it is
probably correct. Note 0.2 closes this as a side effect if the soak ends.

### 1.4 Two anon-callable RPCs — **S**

- `flights_used_this_month(p_couple_id)` — referenced by zero RLS policies, so the grant buys
  nothing. `revoke all … from public, anon, authenticated`, grant to `authenticated` only if a
  caller turns up, and add the membership check it lacks.
- `is_support_admin(check_id)` and its three siblings — the `DEFAULT auth.uid()` path is correct and
  load-bearing; the exposure is the parameter. Either revoke `anon` (they are only called by
  policies and by signed-in code) or drop the parameter and read `auth.uid()` unconditionally, with
  a separate internal function for the admin console's own lookups.

---

## Phase 2 — Data at rest

The inventory and the reasoning are in the backlog's round 3. This is the execution order. Do 2.1
and 2.2 in one change — a class without a migration protects only new installs.

### 2.1 Per-write protection classes — **M**

`.completeFileProtection`, with the same option on the directory so a future writer that forgets
still lands correctly:

- `OfflineDataCache.swift:96`, `OfflineGameStateCache.swift:85`, `GameContentStore.swift:246`
- `PendingMemoryStore.swift:54, 60` + directory at `:20-24`
- `PendingTripStore.swift:80` + directory at `:56-60`
- `MemoryPhotoDiskCache.swift:65` + directory at `:37-41` — the largest concentration of sensitive
  bytes on the device
- `RemoteImageDiskCache.swift:54` + directory at `:27-31`
- `CoupleHistoryPDFExporter.swift:139`, `RelationshipRecordWriter.swift:66`,
  `CoupleDataExporter.swift:412, 440` + the export tree at `:135-139`, and explicitly on the zip
  after `copyItem` at `:458-461`, because a copy carries the coordinator's class rather than ours

`.completeUntilFirstUserAuthentication`, set **explicitly** rather than inherited, on all six
`WidgetImageCache` writes (`:33, 55, 75, 91, 101, 115`). This is the strongest class that works:
the Live Activity's Lock Screen view reads the airline logo, five widgets declare Lock Screen
families, and `DrawingPadWidget` writes from `getTimeline`. Setting it explicitly documents the
decision and stops a future blanket change raising it silently.

Leave the PostHog and RevenueCat directories alone, and do **not** set a class on the Application
Support root — that would sweep them in.

**Do not use `com.apple.developer.default-data-protection`.** It would classify the App Group files
the main app writes at Complete and blank the widgets on every locked render, and every one of
those writes is `try?`, so nothing would log it.

### 2.2 Migrate files already on disk — **M**

A class on a write does nothing to what is already there; a long-standing install keeps its 250 MB
photo cache at CUFUA forever, because `MemoryPhotoDiskCache.write` only runs for photos `has(path:)`
says are missing.

New `DataProtectionMigration`, called from `TwofoldApp.init()` beside the other two configures.
`FileManager.setAttributes(.protectionKey:)` walked with `FileManager.enumerator` — it rewraps the
per-file key without touching bytes, so it is fast even on the photo cache. Version-stamped in
`UserDefaults` so it runs once. Skip files already at the right class, so a run interrupted by a
kill resumes cheaply.

**The guard that matters:** raising CUFUA to Complete needs the class-A key, which does not exist
while the device is locked, and the app can be launched into the background while locked. Guard on
`UIApplication.isProtectedDataAvailable`, retry on `protectedDataDidBecomeAvailableNotification`,
and do not stamp the version on a locked run.

### 2.3 Exclude the derivable stores from backup — **S**

A protection class has no effect on backup inclusion, so this is a separate lever.

`isExcludedFromBackup` on `OfflineDataCache.json`, `OfflineGameStateCache.json`, `GameContent.json`
and the App Group image files — all re-derived on the next online launch.

**Not** on `PendingMemories/` or `PendingTrips/`: those are the only copy, and a user restoring to a
new phone must not lose a memory drafted before pairing.

### 2.4 Keychain: `ThisDeviceOnly` — **M**

supabase-swift writes the refresh token at `kSecAttrAccessibleAfterFirstUnlock`, so an unencrypted
backup restored onto another device carries a live session. Not configurable through
`SupabaseClientOptions`; supply a custom `AuthLocalStorage` writing at
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, service `supabase.gotrue.swift`.

**The risk is the migration, not the change.** Read the existing item at the old accessibility and
rewrite it at the new one on first run, or **every signed-in user is silently signed out on
update**. Test by installing the old build, signing in, then upgrading in place.

### 2.5 Move two stores out of plists you do not own — **M**

Neither can take a protection class or a backup exclusion while it lives in a preferences plist.

- `pendingFlightShares` → a JSON file in the App Group container at `.completeFileProtection`.
  Nothing reads it while locked: a share sheet cannot open on a locked device and the main app reads
  it in the foreground. It only sits at CUFUA because it shares the widget snapshot's plist.
- `pendingGameResponses` → `Application Support` at `.completeFileProtection`. Free-text answers to
  intimate questions.

Both need a one-time read-through of the old key so nothing queued before the update is lost. Do
2.5 together with 1.2, since both touch `PendingShareStore`.

### 2.6 Say what happens without a passcode — **S**

With no device passcode, class keys are derived without a user secret and `.completeFileProtection`
degrades silently to nothing. Application-level encryption does not fix this either — a Keychain key
degrades the same way.

`AppLockService.swift:37-39` already computes this exact condition and uses it only to grey out a
toggle. One line of Settings copy near the App Lock row, saying the app's photos and answers are
encrypted with the device passcode and that iOS cannot encrypt them without one.

**Application-level encryption is not warranted beyond 2.5.** For the widget snapshot specifically
it buys nothing: the widget must decrypt while locked, so the key would sit at `AfterFirstUnlock` in
a shared Keychain group — the same unlock semantics as CUFUA — at the cost of a new entitlement on
two targets and a provisioning race between the app and the extension.

---

## Phase 3 — Abuse and cost

### 3.1 `/api/support` is an unauthenticated mail relay — **M**

No rate limit, no CAPTCHA, no proof of address control; only a honeypot. Each POST sends mail from
our domain to an attacker-chosen address with up to 5000 attacker-written characters, and the RPC
error is swallowed so the mail goes regardless.

Per-IP and per-email throttle **before** the send, written in its own transaction so a rejection
still counts. Stop swallowing the RPC error.

### 3.2 `add-flight` has no rate limit — **S**

Up to three billed AeroAPI calls per invocation, none cached, and the monthly allowance
deliberately does not gate them. `resolve-flight` got a 40/hour bucket for this reason and
`add-flight` was left out. Add a bucket, and pass the `usage` context it currently omits so the
spend stops recording as `unattributed`.

Order matters: 1.1 first, or the bucket is decorative.

### 3.3 R2 presigned PUT has no size bound — **M**

`_shared/r2.ts` signs host and content-type and nothing else. Supabase Storage enforced a 50 MiB
limit that the migration dropped silently. Add a `content-length-range` condition, and validate
`contentType` against an allowlist per kind rather than accepting any caller string.

### 3.4 Notification abuse — **M**

- `notify-couple-event`: cap `detail` and stop putting it verbatim in the push body.
  `game_reminder` is deliberately absent from `PREFERENCE_COLUMN`, so it skips the preference check
  and cannot be muted, and there is no rate limit — unlimited attacker-chosen text to a partner who
  cannot turn it off. **Product decision needed:** give it a preference column, or a server-side
  cooldown like the one `20261020000000` already built for game turns.
- `notify-connection-request`: the 6-hour throttle lives in `send_connection_request_reminder`, and
  calling the edge function directly skips both the RPC and its ledger. Move the throttle into the
  function, or have the function call the RPC.

---

## Phase 4 — App Lock (verify on hardware first)

### 4.1 Confirm the bypass — **S**

Two agents independently concluded `AppLockView` is a ZStack sibling with `zIndex(1)` while every
sheet and cover is attached to the `Group` beneath it, so UIKit presents them above the lock.
Neither `onOpenURL` nor `consumePendingRoute()` checks `isLocked`, and
`twofold://partner-drawing-pad` needs no id.

Both reasoned from SwiftUI presentation semantics rather than observing it. **Settle it before
building anything:** enable App Lock, background the app, then
`xcrun simctl openurl booted twofold://partner-drawing-pad`.

### 4.2 Gate the entry points — **M**, only if 4.1 confirms

Gate `onOpenURL` and `consumePendingRoute()` on `!(appLock.isEnabled && appLock.isLocked)` and hold
the destination the way `consumePendingRoute` already holds a pending route, re-draining on unlock.
The guard is a smaller change than making the lock a real `fullScreenCover`, which has its own
ordering problem when another cover is already up.

Fix `AppLockView`'s header comment while you are there — it calls itself "the full-screen cover
RootView shows in front of everything else", which is what made this hard to see.

### 4.3 Lock on `.inactive`, not `.background` — **S**

iOS captures the app-switcher snapshot during `.inactive` and `appLock.lock()` fires one phase
later, so the card shows whatever was on screen. `PrivacyCoverView` is an `.overlay` and has the
same modal-layering problem as the lock.

---

## Phase 5 — Promises we are not keeping

Each of these is a mismatch between shipped copy and shipped behaviour. Fix the behaviour or the
copy, but do not leave them disagreeing.

- **5.1 Support content.** The policy says support messages are "not stored in the Twofold
  database". `support_requests` holds email, name, subject and message, and `profile_id`
  deliberately has no FK so the record outlives the account — so a "please delete my account"
  ticket survives the deletion it asked for. **Decision needed:** retention window, or corrected
  copy.
- **5.2 Deletion claims.** Reconcile the policy's "your uploads are deleted" and "no longer than 7
  days" with whatever 0.1 and 0.2 land on.
- **5.3 `store: false` on the OpenAI call** — **S**. The flight-email prompt carries the scraped
  boarding pass text, and `store` defaults to true on the Responses API, so it sits in the
  organisation's Logs dashboard for 30 days. Confirm the default against current docs first. The
  disclosure itself is accurate and no identifier ties the request to a user — that part is right.
- **5.4 RevenueCat** — **S**. It receives the account email, by a comment's own admission "purely so
  a person is findable in that dashboard", and that is not disclosed where OpenAI and PostHog are.
  Account deletion also never deletes the RevenueCat customer. Either disclose and delete, or stop
  sending the email.
- **5.5 `partner_subscription_lapse_partner_name`** — **S**. `leave_couple` copies the leaver's first
  name onto the remaining partner's row and `scrub_account` does not null it, so a third party's
  name persists on a "Deleted User" row. One line in `scrub_account`.

---

## Phase 6 — Defence in depth and hygiene

- **6.1 Revokes that do not hold** — **S**. Supabase's default privileges grant `anon` and
  `authenticated` an explicit EXECUTE on every new function, so `revoke … from public` leaves them
  standing. The new admin functions use the weak form. Every one of them checks
  `is_support_admin()`/`is_billing_admin()` first, so this is defence-in-depth — but it is the same
  discrepancy that let `purge_couple_data` sit open. Always `from public, anon, authenticated`.
- **6.2 `places` is globally readable** — **M**. `USING (true)` for authenticated, no owner column,
  and a typed address or dropped pin writes exact coordinates with the typed name. Unattributable,
  which is why it is not urgent. Replace the blanket select with a lookup RPC.
- **6.3 Two log lines** — **S**. `WeatherService.swift:63` logs a home city; `/api/waitlist:105` logs
  a nodemailer rejection whose envelope carries the signup's email.
- **6.4 Security response headers** — **S**. No CSP, no `frame-ancestors`, no `Referrer-Policy`. The
  Supabase SSR cookies are necessarily readable by JavaScript, so any XSS is full session theft
  including an admin's. No XSS sink exists today; a CSP is the cheap insurance.
- **6.5 `x-pathname`** — **S**. Set on the response, so it never reaches the layout and the
  bookmark-preserving redirect has never worked. What does reach it is a client-supplied header. No
  open redirect today — the callback's `/^\/(?!\/)/` is the only thing preventing one. Forward it
  properly and validate it with the same regex.
- **6.6 `InviteCode.code(from:)`** — **S**. `twofold://invite/CODE` is dead because `invite` is the
  host, not a path component, so the backward-compatibility branch is unreachable.
  `twofold://<anyhost>/invite` returns the code `"INVITE"` and shadows widget routing. Zero test
  coverage on a function that gates pairing.
- **6.7 `reset-password` error text** — **S**. `error_description` from an untrusted URL goes
  verbatim into a system alert, so any installed app can put its own sentence in front of the user.
  Show the static copy unless a recovery is actually pending.
- **6.8 One-tap pairing** — **M**. A deep-linked invite prefills the code and sends `origin: .link`,
  which auto-accepts with no inviter approval. The onboarding route for the same link shows the
  inviter's name and avatar first; the signed-in route resolves the same information only *after*
  redemption. Resolve it before enabling Connect.
- **6.9 `connection_accepted` never fires on auto-accept** — **S**. The redeemer calls it but the
  function assumes the caller is the inviter, so the match inverts and it 403s, silently. Migration
  `20261008000000` justifies unsupervised link pairing partly on "the inviter is told".

---

## Decisions needed from you

These are product or policy calls, not engineering ones, and they block the items named.

1. **Support retention** (5.1) — how long, and does a deletion request purge the ticket that asked
   for it?
2. **`game_reminder` mutability** (3.4) — a preference column, or a cooldown?
3. **The soak** (0.2) — has it ended?
4. **RevenueCat email** (5.4) — disclose it, or stop sending it?

## Verification notes

- **Protection classes cannot be tested on the simulator.** It does not implement data protection;
  every file reports `NSFileProtectionNone`, so a test asserting a class passes vacuously. Assert at
  the call site that the write passes the option, and check the real class on hardware.
- **App Lock (4.1) needs a device or simulator run**, not a unit test — it lives in `body` and
  `@State`.
- **0.1 needs a dry run** before the drain is enabled. It is the only item here that destroys data.
- Everything in Phase 1, 5 and 6 is reachable by pgTAP or an existing Swift suite.

## Suggested sequencing

Phase 0.1 alone first, carefully, because it is the only one with a deadline. Then Phase 1 as a
single batch — four small changes, all with tests, all independently verifiable. Then Phase 2 as one
release, since a class without a migration protects only new installs. Phases 3–6 can be picked off
in any order; 4.1 is fifteen minutes and decides whether Phase 4 exists at all.
