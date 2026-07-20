# Twofold Feedback Board

Public feature-request board (Canny/Linear/GitHub-Discussions-style) for Twofold.
Next.js 15 App Router + TypeScript + Tailwind v4 + shadcn/ui + Supabase + TanStack Query + Zod.

Deployed separately from the marketing site (`site/`) and the Sanity Studio
(`site/studio/`) — its own Vercel project, rooted at this folder. Uses the **same**
Supabase project as the main app (`ipfzswswwukfqphloojo`), but with its own migrations
folder (`supabase/migrations/`, separate from the repo-root one) and its own auth
(magic-link email + Google — not the app's Apple Sign-In).

Nothing here ever touches the repo-root `supabase/` folder or `Twofold/` (the iOS app)
— see "Database" below for exactly what commands are safe to run against the shared
database.

## Structure

- `src/app/feedback/` — the board (list, filters, search, submit)
- `src/app/feedback/[slug]/` — feature detail (vote, comments, dev updates, subscribe)
- `src/app/roadmap/`, `src/app/changelog/`
- `src/app/auth/` — sign-in (magic link + Google) and the OAuth/magic-link callback route
- `src/app/admin/` — gated by `is_feedback_admin()`, once Phase 7 lands
- `src/components/feedback/`, `src/components/admin/`, `src/components/layout/`
- `src/lib/supabase/{client,server,middleware}.ts` — `@supabase/ssr` wiring
- `src/lib/db/types.ts` — generated Supabase types (placeholder until Phase 2)
- `src/lib/queries/` — TanStack Query hooks (Phase 2+)
- `src/lib/validation/` — Zod schemas (Phase 2+)
- `supabase/migrations/` — this app's own migrations, applied to the shared project

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

Vercel project, Root Directory = `site/feedback`. Add an Ignored Build Step so commits
to `Twofold/`, repo-root `supabase/`, or the marketing `site/` don't trigger a rebuild:
```
git diff --quiet HEAD^ HEAD -- site/feedback
```
Env vars: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`,
`NEXT_PUBLIC_SITE_URL` (production URL, used to build the auth callback redirect).

Also add `<production-url>/auth/callback` to the shared Supabase project's Auth →
Additional Redirect URLs.
