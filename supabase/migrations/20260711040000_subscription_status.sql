-- Each device writes only its own profile row with its own last-known local StoreKit
-- entitlement — subscriptions are pure on-device StoreKit with no cross-partner sync, but
-- "your partner doesn't pay anything" means access should be granted if *either* partner's
-- profile shows an active subscription. No RLS changes needed: profiles already has an
-- update-own-row policy (used today by updatePartnerNickname/updateAnniversaryDate) and a
-- select policy that already lets a couple member read their partner's profile row (used
-- today by fetchCoupleState).

alter table public.profiles
  add column subscription_active boolean not null default false,
  add column subscription_checked_at timestamptz;
