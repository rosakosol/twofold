# twofoldapp.com.au

The whole public web presence for Twofold, plus the internal console — one Next.js 16 App
Router app (TypeScript + Tailwind v4 + shadcn/ui on `@base-ui/react` + Supabase +
TanStack Query + Zod). Four things live here:

- the **marketing site** — home, features, pricing, quiz, FAQ, support, legal
- the **feedback board** — a public feature-request board (Canny/Linear-style)
- the **account portal** — what someone can do about their own account without emailing us
- the **console** — the internal admin/support tooling, in its own shell at `/admin`

Plus the embedded **Sanity Studio** at `/studio`, which is where marketing copy is edited.

Originally two separate projects (a static Cloudflare Pages marketing site plus this
feedback board); the marketing site was rewritten into this app on 2026-07-21 and promoted
to live at `site/` once the old Cloudflare project was retired. A few things still carry
that history — see `.well-known/apple-app-site-association`, which exists here because
invite links silently stopped opening the iOS app when Cloudflare stopped serving them.

## One account, one database

This app uses the **same Supabase project as the iOS app** (`ipfzswswwukfqphloojo`) and the
**same three sign-in methods**: email + password, Apple, and Google. That is deliberate and
load-bearing rather than incidental — somebody who subscribes on `/pricing` has to arrive in
the app holding the same account, so a fourth identity here would be a stranded subscription.

Magic links used to be the board's only sign-in and are gone: the app's sign-in screen has
no one-time-link option, so anybody who signed up by link arrived at the app with no password
and no way in except "Forgot password?", which is a door labelled for somebody who had one.
`/auth/reset-password` handles recovery for both origins, and on an iOS device with the app
installed it opens the app instead of the browser.

Nothing here touches `Twofold/` (the iOS app). See **Database** for what is safe to run.

## Structure

| Path | What |
| --- | --- |
| `src/app/(marketing)/` | home, features, pricing, quiz, FAQ, support, privacy, terms |
| `src/app/(board)/feedback/` | the board (list, filters, search, submit) + `bookmarks/` |
| `src/app/(board)/account/` | the account portal — subscription, partner, password, deletion |
| `src/app/(board)/auth/` | `sign-in`, `reset-password`, `callback` |
| `src/app/(console)/admin/` | console: moderation, support queue, users, requests, games, usage |
| `src/app/studio/` | embedded Sanity Studio (`next-sanity`), incl. the custom FAQ tool |
| `src/app/api/{support,waitlist}/` | form handlers; send mail via `src/lib/mail/` |
| `src/app/.well-known/…` | Apple App Site Association, for iOS Universal Links |
| `middleware.ts` | Supabase session refresh, on five path prefixes only |

There is no per-feature detail route on the board: a request is read and voted on from the
list row itself. The console has one (`admin/requests/[id]`) because editing needs a form.

### Components and lib

| Path | What |
| --- | --- |
| `src/components/ui/` | shadcn primitives — built on `@base-ui/react`, not Radix |
| `src/components/{marketing,feedback,account,console,admin,layout,auth}/` | feature components |
| `src/lib/supabase/` | `@supabase/ssr` wiring: `client`, `server`, `middleware`, `functionError` |
| `src/lib/marketing/` | Sanity fetchers, in-code fallbacks, billing, auth helpers, price display |
| `src/lib/account/` | `subscription.ts` — what a person may be told and offered about their own billing |
| `src/lib/auth/` | `useUser`, `useAdminRoles`, `isAdmin`, `isConsoleAdmin`, `signOutAndGoHome` |
| `src/lib/queries/` | TanStack Query hooks, plus `queryKeys.ts` and `authorProfiles.ts` |
| `src/lib/mail/` | Zoho SMTP transport + the HTML templates it renders |
| `src/lib/db/types.ts` | generated Supabase types — see **Database** for how |
| `src/lib/validation/` | Zod schemas |
| `src/styles/`, `(marketing)/marketing.css`, `(board)/feedback/feedback.css` | the CSS that is not Tailwind |

Two design systems live side by side on purpose: `(marketing)` dresses bare elements with
`marketing.css`, `(board)` and `(console)` use shadcn. Anything shared between them —
`EmailPasswordForm` and `PasswordResetPanel` — takes chrome slots for the field and submit
elements, so the validation and the wording can be shared without dragging one system into the
other's half of the app. `PasswordStrengthMeter` makes the same compromise a different way:
everything it styles itself is inline and system-neutral.

`.board-page-title` in `globals.css` is the one type token both groups read — the page titles on
`/feedback`, `/account` and `/feedback/bookmarks` were three different sizes until they shared it.

### The console is a separate shell

`(console)` is a route group, so the URLs do not move — `/admin` and `/admin/games` are
exactly where they were. Only the chrome changes, and the gate: the layout checks
`is_console_admin` (**any** role) rather than `is_feedback_admin`, which since the role split
means `content` specifically. Gating the door on one role would lock a billing-only admin out
of the console entirely. Each page inside still checks the role it needs — `content`,
`support` or `billing`, all three answered in one round trip by `my_admin_roles()`.

## Content model

Everything in Studio is either a **singleton** (one document at a fixed `_id`, wired up in
`src/sanity/deskStructure.ts`) or a **free-form list** editors add to and remove from:

| Content | Shape | Fallback when unpublished |
| --- | --- | --- |
| Home hero | singleton `hero` | inline in `src/app/(marketing)/page.tsx` |
| Features | **free-form list** (`feature`) | `src/lib/marketing/featuresFallback.ts` |
| Pricing plans | singletons `plan-plus` / `plan-premium` | `PLANS` in `src/lib/marketing/config.ts` |
| Plan comparison table | singleton `planComparison` | `src/lib/marketing/planComparisonFallback.ts` |
| Quiz | free-form `quizQuestion` + 2 result singletons | quiz hidden if unplayable |
| Privacy / Terms | singletons `legalPage-privacy` / `legalPage-terms` | inline JSX in each page |
| FAQ | **not Sanity** — Supabase `faq_entries` | `src/lib/marketing/faqFallback.ts` |

Features carry their own title, copy, bullets, icon, colour, and `order`, so adding,
removing, renaming and reordering cards is entirely a Studio operation — both the home page
grid and `/features` render whatever is published. The one piece still in code is the
per-feature illustration on `/features` (`FeatureArt`, keyed by the feature's slug); a
feature whose slug has no `case` there falls back to a generic mock card.

Sanity reads go through the CDN with `useCdn: true` and a **60-second** `revalidate`
(`SANITY_REVALIDATE_SECONDS`); `faq_entries` uses the same window. So published copy appears
within a minute without a deploy, and a missing document falls back rather than breaking.

FAQ is not a Sanity type because the iOS app reads the same rows (Settings → Support). The
Studio's custom tool (`src/sanity/tools/FaqTool.tsx`) writes to `faq_entries` directly as the
signed-in admin, gated by the `faq_entries_admin_write` RLS policy — there is no shared secret
any more, and if `NEXT_PUBLIC_FAQ_ADMIN_SECRET` is still set anywhere, delete it.

### Scripts

Studio is the source of truth for everything above — the fallbacks only apply when a document
is missing entirely. The scripts in `scripts/` author or re-author a document from code; each
one overwrites, so re-read `/studio` before running any of them.

| Script | Writes | Flags |
| --- | --- | --- |
| `seed-sanity.mjs` | the feature cards | create-only; `--replace` to overwrite |
| `seed-privacy-policy.mjs` | `legalPage-privacy` | dry-run by default; `--write` to publish |
| `seed-terms.mjs` | `legalPage-terms` | dry-run by default; `--write` to publish |
| `update-plan-copy.mjs` | plan + comparison copy, and the code fallbacks | `--dry` to preview |
| `warm-dev.mjs` | nothing — wraps `next dev`, see below | |

`scripts/lib/` holds the shared Sanity write client (resolves a token from `SANITY_AUTH_TOKEN`,
else the one `sanity login` stored) and the Portable Text builders the legal-page scripts use.

House style for copy in Sanity, in `faq_entries` and in the in-code fallbacks: a plain hyphen,
never an em or en dash. `20261111001400` normalised the rows after nineteen of them had drifted;
it uses `replace()` rather than restating each answer, because the Studio FAQ tool writes these
rows directly and a punctuation pass must not revert an admin's edit.

`faqFallback.ts` describes itself as a character-for-character mirror of those rows. It is not
currently — see the note at the end of this file.

## Local development

```
npm install
npm run dev          # http://localhost:3000
```

`npm run dev` runs `scripts/warm-dev.mjs`, which wraps `next dev --turbopack` and pre-compiles
the heavy routes as soon as the server is ready — Sanity Studio alone is a ~30s cold Turbopack
compile, and the console's dynamic routes were each eating ~6s on first click. Use
`npm run dev:plain` for plain `next dev` with no warm-up.

Requires `.env.local` — copy `.env.local.example`, which documents every variable and why it
is or is not public. In short:

| Variable | Needed for |
| --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` / `_ANON_KEY` | everything |
| `NEXT_PUBLIC_SANITY_PROJECT_ID` / `_DATASET` / `_API_VERSION` | marketing copy + Studio |
| `NEXT_PUBLIC_REVENUECAT_WEB_BILLING_API_KEY` | web checkout on `/pricing` |
| `ZOHO_SMTP_USER` / `_PASSWORD` / `_HOST` / `_PORT` | `/api/support`, `/api/waitlist` |
| `ZOHO_FROM_ADDRESS` | who transactional mail is sent as (`support@`) |
| `ZOHO_ANNOUNCEMENT_FROM_ADDRESS` | optional; announcements as `hello@`, falls back to the above |
| `WAITLIST_NOTIFY_EMAIL` | optional; who hears about a waitlist signup |

There is **no** `NEXT_PUBLIC_SITE_URL`. Auth derives its callback from
`window.location.origin`, because PKCE scopes the code-verifier cookie to the origin that
started the flow — a build-time constant pointing anywhere else fails every exchange. Origins
are configured in Supabase instead (Auth → URL Configuration), and an origin missing from the
Redirect URLs list is silently replaced with Site URL, which is exactly how a sign-in on one
domain completes on another and loses its verifier.

`next dev` also writes `AGENTS.md` and `CLAUDE.md` into this folder and re-creates them if
removed. Both are gitignored at the repo root.

There is no test suite here. The things worth pinning are pinned in the database
(`supabase/tests/`, pgTAP) and in the iOS app's XCTest targets.

### Database

**All migrations live in the repo-root `supabase/migrations/`, not here.**

`site/supabase/` exists and is misleading. It holds 15 migration files from July 2026, and
**none of them has ever been applied** — the tables they describe were created by hand in the
dashboard instead, and were finally captured in source control by repo-root
`20261109000600_feedback_board_schema.sql`, read back from production with
`pg_dump`. The folder is also not linked to any project. Running `db push` from here would
try to create tables that already exist.

So, from the **repo root**:

```
npx supabase link --project-ref ipfzswswwukfqphloojo   # once
npx supabase db push                                   # apply pending migrations
npx supabase test db                                   # pgTAP
```

**Never run `supabase config push`** — it would push `config.toml`'s project-wide settings to
the shared project and could overwrite settings the app depends on.

Types are generated from a **local** stack, not from the remote:

```
npx supabase start && npx supabase db reset            # repo root
npx supabase gen types typescript --local > site/src/lib/db/types.ts
```

`--local` is only safe because of `20261109000600`. Before it, the board's tables existed
only in the linked project, so generating from local **deleted** them from `types.ts` and
broke the build in nine files at once. Keep the hand-written header comment at the top of that
file when you regenerate — it is the record of why.

## Security headers

`next.config.ts` sets a CSP plus `X-Content-Type-Options`, `Referrer-Policy` and
`X-Frame-Options: DENY`. This matters more here than on a typical marketing site: `@supabase/ssr`
must set its auth cookies `httpOnly: false`, because `createBrowserClient` reads the session out
of `document.cookie` for every hook in `src/lib/queries` — so any XSS is full session theft,
including an admin's.

`/studio` is exempt from the CSP only (it mounts Sanity's own application, which loads its own
workers and assets). The other three headers still apply to it.

The CSP allow-lists Stripe and **both** RevenueCat domains. That second one is not cosmetic: the
SDK calls `api.revenuecat.com` but sends telemetry to `e.revenue.cat`, which `*.revenuecat.com`
does not match — and a blocked request there makes the SDK report "Purchase not started due to an
error (error code: 0)", naming neither the domain nor the policy.

`middleware.ts` refreshes the Supabase session on `/account`, `/admin`, `/feedback`, `/studio`
and `/auth` only. It used to match everything but static assets, which meant a signed-in visitor
paid a round trip to Sydney on every marketing page — pure latency on the pages people hit first.

## Deploy

Vercel project, Root Directory = `site`, region `syd1` (`vercel.json`) to sit next to the
Supabase project. Add an Ignored Build Step so commits to `Twofold/` or the repo-root
`supabase/` don't trigger a rebuild:

```
git diff --quiet HEAD^ HEAD -- site
```

Set every variable from the table above in Vercel. Then, in the shared Supabase project:

- Auth → URL Configuration → Redirect URLs: add `<production-url>/auth/callback`, and
  `http://localhost:3000/auth/callback` for dev
- Auth → URL Configuration → Site URL: the production domain

Edge functions and migrations deploy from the repo root, not from here.

## Known drift

`src/lib/marketing/faqFallback.ts` is the cold-start copy of `faq_entries`, and its own comment
calls it "a MIRROR, not an independent copy". Comparing the two (23 rows each) as of
2026-09-30, eleven answers differ:

- **`What's the difference between Plus and Premium?` is materially wrong in the fallback.** It
  lists Word Search and Connect 4 as Plus features. `20261111000700` made both Premium-only and
  `20261111000800` corrected the row; the fallback was not updated. If Supabase is unreachable,
  the FAQ page advertises two Premium games as included in Plus.
- Six differ only by arrow character: the rows use `→` (`Settings → Help`), the fallback `->`.
  Worth settling in one direction — the rows are canonical, so the fallback is the one to change.
- Four differ in wording, mostly where the row was later edited to drop a hardcoded address
  (`reach out below` vs `reach out via support@…`).
- One question was renamed in the rows (`Does Twofold track my location continuously?`) and the
  fallback still has the old title (`How does Twofold use my location?`), so that answer has no
  fallback at all and the old one never renders.

The mirror needs resyncing from the rows. Nothing checks it, which is how it drifted.
