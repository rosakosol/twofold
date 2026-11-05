# Pending migrations

SQL that is written and reviewed but must not go out yet. The Supabase CLI only reads
`supabase/migrations/` and `supabase/tests/`, so nothing here is touched by `db push`, `db reset` or
`test db` until it is moved.

## admin_mfa_enforcement.sql

Stage 2 of admin MFA (security review, F1). Once applied, an admin's powers need an `aal2` session.
Stage 1 is `migrations/20261124000000_admin_mfa_console_access.sql` plus the console's MFA pages, and
has to be live first.

**Do not move it until every admin has a verified factor.** The check and the lockout recovery are in
the file's header, and its first statement refuses to apply if anyone on the roster has none.

To move it, from the repo root (Git Bash):

```sh
last=$(ls supabase/migrations | tail -1 | cut -d_ -f1)
next=$((last + 100))
git mv supabase/pending/admin_mfa_enforcement.sql "supabase/migrations/${next}_admin_mfa_enforcement.sql"
git mv supabase/pending/admin_mfa_enforcement_test.sql supabase/tests/admin_mfa_enforcement_test.sql
git apply supabase/pending/admin_mfa_enforcement_tests.patch
git rm -f supabase/pending/admin_mfa_enforcement_tests.patch
npx supabase db push
```

The version is worked out from the last file, not from today's date: this repo's versions run ahead
of the calendar, and `db push` refuses a version older than the newest one applied.

`admin_mfa_enforcement_tests.patch` gives the 17 existing pgTAP files that act as an admin an aal2
session. They set claims with no `aal`, so they fail once enforcement is on. It only touches test
fixtures, and was generated and run against the file above: 101 files, all passing. If those tests
have changed by then and it no longer applies, the change is the same each time: add `"aal":"aal2"` to
any claims naming a `sub`, and for a file using the legacy `request.jwt.claim.sub`, add
`select set_config('request.jwt.claims', '{"aal":"aal2"}', true);` after `begin;`.
