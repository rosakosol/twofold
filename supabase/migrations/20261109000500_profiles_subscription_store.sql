-- ---------------------------------------------------------------------------
-- Which storefront sold the subscription
-- ---------------------------------------------------------------------------
--
-- The profile records `subscription_active`, `subscription_tier`, `subscription_started_at` and
-- `subscription_will_renew`, but not where the money goes. That gap is fine while the only thing
-- reading it is the app, which never offers to cancel anything. It stops being fine the moment a
-- web account screen exists, because what that screen may offer depends entirely on the answer:
--
--   * An App Store subscription is not ours to cancel. Apple provides no mechanism, which is why
--     `DeleteAccountView` warns and links out to their own subscription settings.
--   * A website subscription bills through Stripe with credentials we hold, and
--     `_shared/subscription-cancel.ts` already knows how to end one.
--
-- Without the distinction on the row, an account screen has to either show a cancel button that
-- silently does nothing for most people, or refuse everyone including those it could actually
-- help. The same column answers it for the support console, which needs to know before telling
-- someone what can be done for them.
--
-- ---------------------------------------------------------------------------
-- Recorded, not fetched
-- ---------------------------------------------------------------------------
--
-- `revenuecat-webhook` already has the whole subscriber record in hand when it writes the other
-- four columns, and `resolveStore` reads the store off exactly the subscription
-- `resolveWillRenew` already reads. Asking RevenueCat per page view would add a network
-- round-trip to a screen that otherwise needs none, and a second way for it to fail.
--
-- ---------------------------------------------------------------------------
-- Null means unknown, and unknown means offer nothing
-- ---------------------------------------------------------------------------
--
-- Nullable and unconstrained, on purpose.
--
-- Nullable because every existing subscriber has no store recorded until their next webhook event
-- or the nightly `reconcile-subscriptions` pass, so null is a real state that will be common for a
-- while and has to read as "we do not know yet" rather than as anything about the subscription.
--
-- Unconstrained because RevenueCat can add a storefront whenever it likes, and a check constraint
-- would turn that into a failed subscription write — trading a cosmetic unknown for a real outage
-- in the one path that records who has paid. `_shared/subscription-cancel.ts` already handles an
-- unrecognised store by refusing to act on it rather than guessing, and that is the rule here too:
-- every consumer must treat null, and anything it does not recognise, as "do not offer to cancel".
-- Erring the other way produces a button that claims to have cancelled something it cannot reach,
-- and the person discovers otherwise when they are charged again.

alter table public.profiles
  add column if not exists subscription_store text;

comment on column public.profiles.subscription_store is
  'Storefront that sold the active subscription, lowercased ("app_store", "stripe", '
  '"rc_billing", "promotional"…), as reported by RevenueCat and written by revenuecat-webhook. '
  'Null means unknown — not yet seen by the webhook, or no subscription. Consumers must treat '
  'null and any unrecognised value as "not ours to cancel".';

-- ---------------------------------------------------------------------------
-- Locked from clients, the way the other four are
-- ---------------------------------------------------------------------------
--
-- By default this column is already unwritable by a client, because 20260915000000 removed the
-- table-level UPDATE on `profiles` and re-granted the harmless columns one by one — a new column
-- simply gets no grant. (Verified on a local stack: `has_column_privilege('authenticated', ...,
-- 'subscription_will_renew', 'UPDATE')` is false, and that column was added the same way.)
--
-- That is not enough on its own, and that migration says why at length: a single
-- `grant all on all tables in schema public to anon, authenticated` re-opens every column at once,
-- silently, and this repo has run exactly that statement before to fix a missing-grant outage. The
-- guarantee that survives it is the trigger, because a trigger is not a privilege and no GRANT
-- restores the write.
--
-- So the trigger's column list gains this one. Rewritten in full rather than patched, since
-- `create or replace function` takes the whole body — which means this must be built on the
-- CURRENT definition, not on the one in 20260915000000. That migration named three columns;
-- 20261001000000 and 20261002000000 each added more as they were introduced, and rewriting from
-- the original text silently reverts theirs. `redundant_subscription_test` catches exactly that,
-- and did.
create or replace function private.reject_client_subscription_writes()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user not in ('anon', 'authenticated') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if coalesce(new.subscription_active, false)
      or new.subscription_tier is not null
      or new.subscription_checked_at is not null
      or new.subscription_started_at is not null
      or new.subscription_will_renew is not null
      or new.subscription_store is not null
    then
      raise exception 'the subscription columns are set by the subscription webhook, not by the client'
        using errcode = '42501';
    end if;
    return new;
  end if;

  if new.subscription_active is distinct from old.subscription_active
    or new.subscription_tier is distinct from old.subscription_tier
    or new.subscription_checked_at is distinct from old.subscription_checked_at
    or new.subscription_started_at is distinct from old.subscription_started_at
    or new.subscription_will_renew is distinct from old.subscription_will_renew
    or new.subscription_store is distinct from old.subscription_store
  then
    raise exception 'the subscription columns are set by the subscription webhook, not by the client'
      using errcode = '42501';
  end if;

  return new;
end;
$$;
