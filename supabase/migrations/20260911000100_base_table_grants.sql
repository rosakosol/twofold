-- Grants the API roles table access, so a database built purely from these migrations actually works.
--
-- Production has `grant all` for anon/authenticated/service_role on all 35 public tables — it got
-- them from the hosted project's default privileges, which were in place before any of this repo's
-- migrations ran. None of the migrations ever grant anything, so those privileges exist *only* in
-- production. A fresh `supabase db reset` produced 35 tables with no grants for any API role, and
-- the app failed against it with "permission denied for table couples" — a symptom that reads
-- exactly like an auth or paywall bug and cost real debugging time earlier.
--
-- Safe to grant this broadly because row level security is enabled on every one of these tables in
-- both environments (verified, zero exceptions), which is the standard Supabase model: GRANT opens
-- the table to the role, RLS policies decide which rows it may actually touch. This is the same
-- privilege set production already has, so applying it there is a no-op.
--
-- Functions are deliberately untouched. Postgres grants EXECUTE to PUBLIC by default, so RPCs work
-- in a fresh database with no help — and several security definer functions rely on that default
-- being explicitly revoked and re-granted narrowly (e.g. `list_couple_day_bounds` is service_role
-- only). A blanket routine grant would quietly widen those back open.

grant all on all tables in schema public to anon, authenticated, service_role;
grant all on all sequences in schema public to anon, authenticated, service_role;

-- The statements above only cover tables that exist right now. These make every table a later
-- migration creates inherit the same grants, so this problem can't silently come back.
alter default privileges for role postgres in schema public
  grant all on tables to anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  grant all on sequences to anon, authenticated, service_role;
