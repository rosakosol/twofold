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

- `src/app/(marketing)/` — home, features, pricing, FAQ, privacy, terms
- `src/app/studio/` — embedded Sanity Studio (`next-sanity`), incl. the custom FAQ tool
- `src/sanity/` — Sanity config/schema (hero, features, legal pages, quiz, plans — FAQ
  is intentionally not a Sanity document type, see `src/sanity/tools/FaqTool.tsx`)
- `src/app/(board)/feedback/` — the feedback board (list, filters, search, submit)
- `src/app/(board)/feedback/[slug]/` — feature detail (vote, comments, dev updates)
- `src/app/(board)/admin/` — gated by `is_feedback_admin()`
- `src/app/(board)/auth/` — feedback board sign-in (magic link + Google) + callback route
- `src/components/feedback/`, `src/components/admin/`, `src/components/marketing/`, `src/components/layout/`
- `src/lib/supabase/{client,server,middleware}.ts` — `@supabase/ssr` wiring (feedback board)
- `src/lib/marketing/` — Sanity fetchers + fallback copy for the marketing pages
- `src/lib/db/types.ts` — generated Supabase types (feedback board's own tables)
- `src/lib/queries/` — TanStack Query hooks
- `src/lib/validation/` — Zod schemas
- `supabase/migrations/` — the feedback board's own migrations, applied to the shared project

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
