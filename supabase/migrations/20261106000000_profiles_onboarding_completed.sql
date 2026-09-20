-- The website can create accounts now, and the app still assumes only it can.
--
-- `handle_new_user` (20260708102734) writes a profiles row for every auth.users insert, taking
-- first_name from raw_user_meta_data. The website's sign-in sets no such metadata, so somebody who
-- subscribes on the web gets a real account with an empty name and nothing else. On iOS,
-- `loadSignedInState` then admits them outright — its comment says "Being authenticated at all
-- means onboarding is already done", which was true right up until the web became a second way to
-- create an account. They land in MainTabView called "You", with no partner name, no anniversary,
-- no invite, and no route back to the flow that collects any of it.
--
-- An empty first_name looks like the obvious signal for "never onboarded" and cannot be used as
-- one. `SaveAccountView` persists the name only through `signUp`'s user metadata, and the
-- Apple/Google buttons do not go through `signUp` — they call `applyOnboardingAccount`, which
-- writes the photos, the cities, the partner nickname and the anniversary, and never once writes
-- first_name. So every account that completed onboarding via SSO is *also* sitting on an empty
-- first_name, and keying off it would throw all of them back into onboarding on next launch. (The
-- app-side half of this change fixes that missing write; this column is what makes the distinction
-- storable rather than guessed at.)
--
-- Hence recording the fact instead of inferring it.

alter table public.profiles
  add column if not exists onboarding_completed_at timestamptz;

comment on column public.profiles.onboarding_completed_at is
  'When this account finished in-app onboarding. Null means it never did — a web-created account, '
  'which RootView routes into onboarding with the account-creation and paywall steps skipped.';

-- Backfilled rather than left null, because null is about to mean "send this person through
-- onboarding" and every row that exists right now belongs to someone who already went through it
-- (or to a web test account, which is cheap to fix by hand). Getting this backwards would re-onboard
-- live users, which is much worse than letting one test account past.
--
-- To exercise the new path with an existing account:
--   update public.profiles set onboarding_completed_at = null where id = '<user id>';
update public.profiles
set onboarding_completed_at = created_at
where onboarding_completed_at is null;

-- 20260915000000 revoked table-level UPDATE on profiles and re-granted the ~40 columns one at a
-- time, so a column added afterwards is unwritable by its own owner until it is named here. That
-- migration's comment predicted this exact trap ("Every future `alter table public.profiles add
-- column` needs a matching per-column grant"); this is the first column to walk into it.
grant update (onboarding_completed_at) on public.profiles to anon, authenticated;
