# twofoldapp.com.au

The whole public web presence for Twofold — marketing site, FAQ/pricing/legal pages,
the embedded Sanity Studio, and the public feature-request board (Canny/Linear/GitHub-
Discussions-style) — one Next.js 15 App Router app (TypeScript + Tailwind v4 +
shadcn/ui + Supabase + TanStack Query + Zod). Originally two separate projects (a
static Cloudflare Pages marketing site plus this feedback board); the marketing site
was rewritten into this app on 2026-07-21 and promoted to live at `site/` directly
once the old Cloudflare project was fully retired.

Uses the **same** Supabase project as the main iOS app (`ipfzswswwukfqphloojo`), but
with its own migrations folder (`supabase/migrations/`, separate from the repo-root
one) and its own auth for the feedback board (magic-link email + Google — not the
app's Apple Sign-In). `faq_entries` (used by both this site's `/faq` page and the iOS
app's Settings > Support screen) lives in the repo-root Supabase project instead —
see the Studio's custom FAQ tool (`src/sanity/tools/FaqTool.tsx`).

Nothing here ever touches the repo-root `supabase/` folder or `Twofold/` (the iOS app)
— see "Database" below for exactly what commands are safe to run against the shared
database.

## Structure

- `src/app/(marketing)/` — home, features, pricing, quiz, FAQ, support, privacy, terms
- `src/app/api/{support,waitlist}/` — form handlers; send mail via `src/lib/mail/`
- `src/lib/mail/` — Zoho SMTP transport + the HTML email templates it renders
- `src/app/studio/` — embedded Sanity Studio (`next-sanity`), incl. the custom FAQ tool
- `src/sanity/` — Sanity config/schema (hero, features, legal pages, quiz, plans — FAQ
  is intentionally not a Sanity document type, see `src/sanity/tools/FaqTool.tsx`)
- `src/app/(board)/feedback/` — the feedback board (list, filters, search, submit) and
  `feedback/bookmarks/`. There is no per-feature detail route: a request is read and
  voted on from the list row itself
- `src/app/(board)/admin/` — gated by `is_feedback_admin()`
- `src/app/(board)/auth/` — feedback board sign-in (magic link + Google) + callback route
- `src/components/feedback/`, `src/components/admin/`, `src/components/marketing/`, `src/components/layout/`
- `src/lib/supabase/{client,server,middleware}.ts` — `@supabase/ssr` wiring (feedback board)
- `src/lib/marketing/` — Sanity fetchers + fallback copy for the marketing pages
- `src/lib/db/types.ts` — generated Supabase types (feedback board's own tables)
- `src/lib/queries/` — TanStack Query hooks
- `src/lib/validation/` — Zod schemas
- `supabase/migrations/` — the feedback board's own migrations, applied to the shared project

## Content model

Everything in Studio is either a **singleton** (one document at a fixed `_id`, wired up in
`src/sanity/deskStructure.ts`) or a **free-form list** editors add to and remove from:

| Content | Shape | Fallback when unpublished |
| --- | --- | --- |
| Home hero | singleton `hero` | inline in `src/app/(marketing)/page.tsx` |
| Features | **free-form list** (`feature`) | `src/lib/marketing/featuresFallback.ts` |
| Pricing plans | singletons `plan-plus` / `plan-premium` | `PLANS` in `src/lib/marketing/config.ts` |
| Quiz | free-form `quizQuestion` + 2 result singletons | quiz hidden if unplayable |
| Privacy / Terms | singletons `legalPage-privacy` / `legalPage-terms` | inline JSX in each page |
| FAQ | not Sanity — Supabase `faq_entries`, via the custom FAQ tool | `src/lib/marketing/faqFallback.ts` |

Features carry their own title, copy, bullets, icon, colour, and `order`, so adding,
removing, renaming, and reordering cards is entirely a Studio operation — both the home
page grid and `/features` render whatever is published. The one piece still in code is the
per-feature illustration on `/features` (`FeatureArt`, keyed by the feature's slug); a
feature whose slug has no `case` there falls back to a generic mock card.

### Seed scripts

Studio is the source of truth for everything above — the fallbacks only apply when a
document is missing entirely. The scripts in `scripts/` exist to author or re-author a
document from code; each one overwrites, so re-read `/studio` before running any of them.

| Script | Writes | Flags |
| --- | --- | --- |
| `seed-sanity.mjs` | the feature cards | create-only; `--replace` to overwrite |
| `seed-privacy-policy.mjs` | `legalPage-privacy` | dry-run by default; `--write` to publish |
| `seed-terms.mjs` | `legalPage-terms` | dry-run by default; `--write` to publish |

`scripts/lib/` holds the shared Sanity write client (resolves a token from
`SANITY_AUTH_TOKEN`, else the one `sanity login` stored) and the Portable Text builders the
two legal-page scripts use.

House style for copy in Sanity, in `faq_entries`, and in the in-code fallbacks: a plain
hyphen, never an em or en dash.

## Local development

```
npm install
npm run dev          # http://localhost:3000
```

Requires `.env.local` (copy `.env.local.example` — values are the same public/anon
Supabase URL+key already used by the marketing site, safe to commit-adjacent since
they're not secret).

### Database

This folder has its own `supabase/` config linked to the *same remote project* the app
uses, but is developed against directly (no local Postgres — migrations here
FK-reference `profiles`/`auth.users`, which only exist via the repo-root migrations, so
a fresh local `supabase start` here would be missing them).

```
npx supabase login
npx supabase link --project-ref ipfzswswwukfqphloojo
npx supabase db push          # applies pending migrations in supabase/migrations/
```

**Never run `supabase config push` from here** — only `db push`. `config push` would
push this folder's `config.toml` project-wide settings to the *shared* project and could
overwrite settings the app or another engineer/agent depends on.

After migrations are applied, regenerate types:
```
npx supabase gen types typescript --project-id ipfzswswwukfqphloojo > src/lib/db/types.ts
```

## Deploy

Vercel project, Root Directory = `site`. Add an Ignored Build Step so commits to
`Twofold/` (the iOS app) or the repo-root `supabase/` don't trigger a rebuild:
```
git diff --quiet HEAD^ HEAD -- site
```
Env vars: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`,
`NEXT_PUBLIC_SITE_URL` (production URL, used to build the auth callback redirect).

Also add `<production-url>/auth/callback` to the shared Supabase project's Auth →
Additional Redirect URLs.
