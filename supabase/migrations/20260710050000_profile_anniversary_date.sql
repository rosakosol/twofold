-- Collected during onboarding (personalization, like home_place_id) before a real couple
-- exists — stored per-profile rather than on `couples.started_dating_on`, which stays the
-- source of truth once a couple actually forms. Reconciling the two once pairing happens is
-- follow-up work, same as partner_name/partner city today.

alter table public.profiles add column anniversary_date date;
