-- ---------------------------------------------------------------------------
-- Someone who has already cancelled must stop being asked to cancel
-- ---------------------------------------------------------------------------
--
-- 20261001000000 finds the couple paying twice and names the later purchase. It has a flaw that
-- only appears after someone does what it asks.
--
-- Cancelling an App Store subscription does not end it. It stops the renewal, and the entitlement
-- runs to the end of the period already paid for — up to a year for an annual plan. RevenueCat
-- keeps reporting that entitlement active for the whole of that time, and rightly so: the person
-- is still entitled. So `subscription_active` stays true, the couple still looks doubled up, and
-- the card keeps telling someone to cancel a subscription they cancelled months ago.
--
-- The missing fact is whether a subscription is going to renew. RevenueCat records it as
-- `unsubscribe_detected_at` on the subscription — set the moment a cancellation is detected,
-- regardless of how much paid time is left.
--
-- With that, the rule becomes: only count the partners whose subscriptions will actually renew.
-- Fewer than two of those and there is no ongoing overlap to report, which covers both ways this
-- resolves:
--
--   * the later purchaser cancels — the overlap ends by itself, and nothing more is asked of them
--   * the earlier purchaser cancels instead — their partner's subscription is now the one that
--     carries the couple, which is a perfectly good outcome and also needs no prompting
--
-- Note this deliberately does not wait for the cancelled subscription to expire. The point is to
-- stop asking for an action that has already been taken.

alter table public.profiles
  add column if not exists subscription_will_renew boolean;

comment on column public.profiles.subscription_will_renew is
  'False once RevenueCat reports a cancellation for this profile''s active subscription — it is '
  'still entitled until the paid period ends, but it will not renew. Null when unknown. Written '
  'only by the revenuecat-webhook function.';

-- ---------------------------------------------------------------------------
-- Locked from the client, like the four columns beside it
-- ---------------------------------------------------------------------------
--
-- Same reasoning as 20261001000000: it grants nothing, but a client that could write it could
-- decide which partner gets asked to stop paying — here by marking their own subscription as
-- already cancelled so that their partner's is the only one left to name.
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
  then
    raise exception 'the subscription columns are set by the subscription webhook, not by the client'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- The overlap, counted among subscriptions that are actually continuing
-- ---------------------------------------------------------------------------
create or replace function public.redundant_subscription()
returns table (
  both_subscribed boolean,
  redundant_profile_id uuid,
  i_am_redundant boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_couple public.couples;
  v_a public.profiles;
  v_b public.profiles;
  v_redundant uuid;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select * into v_couple
  from public.couples
  where status = 'active' and (partner_a_id = v_me or partner_b_id = v_me);

  if not found then
    return query select false, null::uuid, false;
    return;
  end if;

  select * into v_a from public.profiles where id = v_couple.partner_a_id;
  select * into v_b from public.profiles where id = v_couple.partner_b_id;

  -- `is not false` rather than `= true`: null means RevenueCat hasn't told us, and an unknown
  -- renewal state has to behave the way it did before this column existed, or every couple whose
  -- webhook hasn't fired since this deployed would silently stop being told anything.
  if not (
    coalesce(v_a.subscription_active, false) and v_a.subscription_will_renew is not false
    and coalesce(v_b.subscription_active, false) and v_b.subscription_will_renew is not false
  ) then
    return query select false, null::uuid, false;
    return;
  end if;

  -- Strictly later wins. Equal dates, or either one missing, leaves this null on purpose: naming
  -- the wrong person costs them a subscription they wanted to keep, and "one of you can cancel" is
  -- a perfectly useful thing to be told.
  if v_a.subscription_started_at is not null and v_b.subscription_started_at is not null then
    if v_a.subscription_started_at > v_b.subscription_started_at then
      v_redundant := v_a.id;
    elsif v_b.subscription_started_at > v_a.subscription_started_at then
      v_redundant := v_b.id;
    end if;
  end if;

  return query select true, v_redundant, v_redundant is not distinct from v_me;
end;
$$;
