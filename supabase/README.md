# Supabase backend

## Running a local stack

```sh
supabase start
supabase db reset     # rebuilds from migrations/ alone
```

`db reset` is expected to work from a clean slate. If it stops working, that's a bug in the
migrations, not something to route around by hand — two things used to exist only in production and
had to be captured before a reset could succeed at all (`feedback_admins`/`is_feedback_admin()`, and
the base-table grants for the API roles).

To point the iOS app at the local stack, tick `SUPABASE_ENV=local` in the Twofold scheme's
environment variables (Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸ Arguments). Don't edit
`SupabaseConfig.swift` — the whole point of the env-var path is that there's nothing to remember to
revert. On a physical device set `SUPABASE_URL` to the Mac's LAN address instead, since 127.0.0.1 is
the phone itself.

## Tests

```sh
# pgTAP — day boundary, streak lapse, couple subscription tier
supabase test db

# Deno — flight refresh cadence and reminder windows
docker run --rm -v "$PWD/..":/app -w /app --entrypoint deno denoland/deno:latest \
  test --allow-all supabase/functions/_shared/flight-schedule.test.ts
```

The Deno tests go through Docker because deno isn't installed on the host; if you install it,
`deno test supabase/functions/_shared/flight-schedule.test.ts` from the repo root does the same
thing.

Anything a cron job or the app calls on a schedule is worth a test here rather than a manual check
against production — the flight cadence in particular decides both the AeroAPI bill and how quickly
a departure is noticed.

## Migration history notes

**`20260830000850_feedback_admins.sql` is marked applied in production, not run there.** Production
already had both objects (created out of band by the feedback app), so the file exists to make a
fresh database reproduce production, and was registered with:

```sh
supabase migration repair --status applied 20260830000850
```

It's written idempotently, so applying it to an environment that already has those objects is a
no-op rather than an error.

**The 27 `*_debug_temp.sql` / `*_drop_debug_temp.sql` files are inert and deliberately kept.** They
were throwaway diagnostic functions created and dropped again while chasing production issues. Every
one is dropped by a committed migration — a fresh reset leaves zero `debug_*` functions behind,
matching production exactly — so they cost nothing but noise.

Deleting them is not worth it: they're already recorded in production's `schema_migrations`, so
removing the files would leave 27 remote versions with no local counterpart and require a
`migration repair` for each before `db push` behaved again. If the ~180-file history ever genuinely
needs tidying, the answer is squashing to a single baseline (`supabase db dump` → one migration,
history reset), which is a deliberate maintenance task — not a file-by-file cleanup.
