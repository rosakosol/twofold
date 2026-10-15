-- `profiles.account_deleted_at` is client-writable, and it is an authorisation input.
--
-- 20260915000000 re-granted UPDATE on every profiles column except the three subscription ones.
-- `account_deleted_at` already existed, so it was swept in. The app only ever reads it
-- (`rejectIfAccountDeleted`); the only writers are `private.scrub_account` and
-- `close_dormant_account`, both security definer. But two things trust it:
--
--   * `admin_purge_couple_archive` purges an archive early only when "both partners must have
--     deleted their accounts". A live partner could PATCH their own row to look deleted and make
--     the shared archive purgeable ahead of the timer the FAQ says neither partner can move.
--   * The reverse: a scrubbed account whose session is still live (the access token outlives
--     `auth.admin.deleteUser` until it expires, and indefinitely if that call failed, which
--     `delete-account` documents as a possible state) could set it back to null and stop being
--     "deleted" to everything that asks.
--
-- Column-level revoke, matching how 20260915000000 locked the subscription columns.

revoke update (account_deleted_at) on public.profiles from anon, authenticated;
