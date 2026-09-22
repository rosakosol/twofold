-- Onboarding drops people at question one, and half of them have already answered it.
--
-- The account is created part-way through the flow, at `.saveAccount`, which sits after the whole
-- questionnaire and before the invite screen, the trial screen and the paywall. Everything the
-- questions collect is written to `profiles` at that moment by `applyOnboardingAccount`. So from
-- there on, a person holds a real, populated account with `onboarding_completed_at` still null —
-- and the paywall is deliberately non-dismissable, so quitting on it is the single most likely way
-- to end up in that state.
--
-- `loadSignedInState` then reads the null and routes them into onboarding at question one, where
-- `OnboardingModel` is rebuilt empty on every launch and knows nothing about the answers already
-- sitting in their profile. They re-answer eighteen screens to arrive back at the paywall they
-- walked away from. Most do not.
--
-- This column is the difference between "has not onboarded" and "has not finished onboarding",
-- which the single existing timestamp cannot express. With it, the app can greet them, say their
-- setup was kept, and put them back on `.invitePartner` — three screens from done, with the
-- paywall still ahead of them rather than buried behind the questionnaire.
--
-- Recorded rather than inferred, the same argument 20261106000000 makes. The fact is guessable —
-- a web-created account has an empty `partner_name` and a null `anniversary_date` where an
-- abandoned in-app one has both — but that guess breaks the moment any of those fields becomes
-- optional, and it breaks silently, in the direction of making somebody redo the questionnaire.

alter table public.profiles
  add column if not exists onboarding_account_created_at timestamptz;

comment on column public.profiles.onboarding_account_created_at is
  'When in-app onboarding created this account, at the `.saveAccount` step. Non-null with a null '
  '`onboarding_completed_at` means the questionnaire is done and the invite/trial/paywall screens '
  'are not — the state OnboardingCoordinatorView offers to resume. Null for accounts created '
  'outside the app (the website), which have answered nothing.';

-- No backfill, unlike 20261106000000, and for the opposite reason.
--
-- Every row that exists now either has `onboarding_completed_at` set, in which case this column is
-- never read, or is a web-created account that genuinely has answered nothing and should still
-- start at question one. Null is already the right answer everywhere, and writing one would be
-- claiming a questionnaire that nobody filled in.

-- 20260915000000 revoked table-level UPDATE on profiles and re-granted the columns one at a time,
-- so a new column is unwritable by its own owner until it is named here. 20261106000000 was the
-- first to walk into that trap and left the warning; this is the second column, and the failure
-- would be silent and would land on exactly the people this migration exists to help.
grant update (onboarding_account_created_at) on public.profiles to anon, authenticated;
