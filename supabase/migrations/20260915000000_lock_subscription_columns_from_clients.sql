-- Any signed-in user could grant themselves — and their partner — Premium, with their own honest JWT.
--
-- `profiles.subscription_active` / `subscription_tier` / `subscription_checked_at` are the entire
-- entitlement record, and until now the client wrote them itself: BackendService.swift's
-- `updateSubscriptionStatus` PATCHes its own profile row with whatever StoreKit reported. There is
-- no RevenueCat webhook yet, so the device's word *was* the source of truth. The policy
-- `profiles_update_self` (20260708102734) lets a user update their own row, and
-- `20260911000100_base_table_grants.sql` handed anon/authenticated `grant all` on every public
-- table with no column restriction. Nothing else stood in the way — no trigger, no check.
--
-- So `PATCH /rest/v1/profiles?id=eq.<my own id>` with `{"subscription_tier":"premium",
-- "subscription_active":true}` was a working paywall bypass requiring no forged token, no stolen
-- key, and no server bug — just curl and the anon key that ships in the app.
--
-- It doesn't stop at one account. `fetchSubscriptionActive` ORs `subscription_active` across both
-- partners, and `private.couple_effective_tier` (20260912000000) does the same for the tier, so one
-- person self-granting silently upgrades their partner too, and `start_deck_session`'s premium gate
-- reads exactly those columns. One row edit unlocks premium content for two accounts.
--
-- This migration takes those three columns away from the client. Everything else on the profile —
-- first_name, timezone, avatar_path, the notification preferences, the dismissal flags — stays
-- exactly as writable by its owner as it is today.
--
-- IMPORTANT: this deliberately breaks `updateSubscriptionStatus`. It must not reach production
-- before the RevenueCat webhook that replaces it, which will write these columns as service_role.
--
-- ---------------------------------------------------------------------------
-- Why a column-level REVOKE is not, on its own, the mechanism
-- ---------------------------------------------------------------------------
--
-- The obvious fix is `revoke update (subscription_active, ...) on public.profiles from
-- authenticated`. It does nothing here. Postgres tracks table-level and column-level privileges
-- separately, and a table-level grant is not decomposed into per-column grants that a column REVOKE
-- can chip away at — it stands on its own and authorises every column. Verified against this
-- schema on a local stack: after that exact REVOKE, `has_column_privilege('authenticated',
-- 'public.profiles', 'subscription_tier', 'UPDATE')` still returned true, because
-- 20260911000100's `grant all` left authenticated holding UPDATE at the table level.
--
-- The revoke only bites if the table-level UPDATE goes away first and the ~40 other columns are
-- re-granted individually, which is done below. But that arrangement is fragile in two specific
-- ways, both of which this repo has already walked into once:
--
--   1. A single `grant all on all tables in schema public to anon, authenticated` re-opens it, in
--      full, silently. That is not hypothetical — 20260911000100 is exactly that statement, it was
--      written to fix a real "permission denied for table couples" outage, and the README
--      recommends it as the cure for that class of bug. The next person to hit a missing grant has
--      a documented precedent for running the one statement that undoes this.
--   2. Every future `alter table public.profiles add column` needs a matching per-column grant, or
--      the client gets "permission denied for table profiles" on a column nobody thought was
--      restricted. `alter default privileges` does not help — it applies to newly created *tables*,
--      never to new columns of an existing one — so the blanket grants in 20260911000100 will not
--      cover them either.
--
-- So the guarantee is a BEFORE trigger, which neither of those can defeat: it is not a privilege,
-- so no GRANT restores the write, and it names the three columns explicitly, so a new column on
-- profiles is unaffected by it. The column grants are kept as well — they make the rejection happen
-- at the privilege check, before the row is even located, which is a cleaner 403 at the API edge
-- and a second thing an attacker would have to get past. If the per-column grants ever become a
-- maintenance nuisance, they can be dropped without reopening the hole; the trigger is what holds.

-- ---------------------------------------------------------------------------
-- The guarantee: a trigger no GRANT can undo
-- ---------------------------------------------------------------------------

-- Not `security definer` — on purpose. It has to see the *caller's* role, and a security definer
-- function would report its owner instead, making every caller look trusted.
--
-- The check is a denylist of `anon` and `authenticated` rather than an allowlist of trusted
-- writers, because those two are precisely and exhaustively the roles a client can reach. Supabase
-- picks the session role from the JWT's `role` claim, and PostgREST's `authenticator` is only a
-- member of anon, authenticated and service_role — a token claiming any other role is rejected
-- before a statement runs. Anything else touching this table (service_role, postgres, a
-- `security definer` function owned by postgres, pg_cron) is already server-side and stays able to
-- write, which is what the incoming webhook needs.
--
-- `is distinct from` rather than `<>` so that a null-to-value change is caught: `subscription_tier`
-- is null on a fresh profile, and `null <> 'premium'` is null, i.e. not true — the exact write this
-- migration exists to stop would have slipped through an inequality test.
create or replace function private.reject_client_subscription_writes()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user not in ('anon', 'authenticated') then
    return new;
  end if;

  -- There is no insert policy on profiles today — rows are created only by `handle_new_user`, which
  -- runs as postgres — so a client cannot insert one. This branch is here so that adding such a
  -- policy later, or an upsert path, doesn't quietly become a way in through the back door.
  if tg_op = 'INSERT' then
    if coalesce(new.subscription_active, false)
      or new.subscription_tier is not null
      or new.subscription_checked_at is not null
    then
      raise exception 'subscription_active, subscription_tier and subscription_checked_at are set by the subscription webhook, not by the client'
        using errcode = '42501';
    end if;
    return new;
  end if;

  if new.subscription_active is distinct from old.subscription_active
    or new.subscription_tier is distinct from old.subscription_tier
    or new.subscription_checked_at is distinct from old.subscription_checked_at
  then
    raise exception 'subscription_active, subscription_tier and subscription_checked_at are set by the subscription webhook, not by the client'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

-- Fires per row and rejects the whole statement, so a multi-column PATCH that bundles first_name in
-- with subscription_tier fails outright rather than applying the harmless half.
--
-- 42501 (insufficient_privilege) is chosen so this and the column grants below report the same
-- error class: whichever of the two catches the write, the client sees a 403, not a 500.
drop trigger if exists trg_profiles_guard_subscription on public.profiles;
create trigger trg_profiles_guard_subscription
  before insert or update on public.profiles
  for each row execute function private.reject_client_subscription_writes();

-- ---------------------------------------------------------------------------
-- Defence in depth: table-level UPDATE off, every other column back on
-- ---------------------------------------------------------------------------

revoke update on public.profiles from anon, authenticated;

-- Enumerated from the live catalogue rather than written out, so this migration cannot drift from
-- whatever columns profiles actually has at the point it runs — ~40 today, across a dozen earlier
-- migrations. anon is re-granted alongside authenticated purely to leave its privileges as they
-- were; RLS still gives it no row it may update, since `profiles_update_self` needs an auth.uid().
do $$
declare
  v_column text;
begin
  for v_column in
    select column_name
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name not in ('subscription_active', 'subscription_tier', 'subscription_checked_at')
    order by column_name
  loop
    execute format('grant update (%I) on public.profiles to anon, authenticated', v_column);
  end loop;
end $$;

-- The webhook's role. Untouched by the revoke above (it named only anon and authenticated), stated
-- here so the intent survives someone reading this file rather than the catalogue.
grant update on public.profiles to service_role;

comment on trigger trg_profiles_guard_subscription on public.profiles is
  'Entitlement columns are server-owned. Rejects any write to subscription_active, subscription_tier or subscription_checked_at from anon/authenticated; see 20260915000000.';
