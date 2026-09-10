-- ---------------------------------------------------------------------------
-- Two people, two subscriptions, one couple
-- ---------------------------------------------------------------------------
--
-- A Twofold subscription covers a couple, not a person: `private.couple_effective_tier` takes the
-- better of the two partners' tiers, and every gate in the app reads that. So the moment two
-- people who both subscribed while single accept each other's connection request, one of those
-- subscriptions stops buying anything at all. It keeps billing, and nothing in the app has ever
-- mentioned it.
--
-- Nobody is cut off and no entitlement changes here. The only thing this adds is the ability to
-- say, to the right person, that they can cancel.
--
-- Which person: the one who subscribed most recently. That is the product rule, and it reads the
-- fair way round — the partner who has been paying longer keeps their subscription, and the one
-- who joined last is the one asked to stop.
--
-- "Most recently" deliberately means the ORIGINAL purchase, not the latest renewal. Renewal dates
-- would name the wrong person almost every time: a monthly subscriber of two years renewed last
-- week, and would always look more recent than someone who bought an annual plan three months ago.
-- The question being answered is who started paying last.
--
-- ---------------------------------------------------------------------------
-- Detected as a standing condition, not at the moment of accepting
-- ---------------------------------------------------------------------------
--
-- The obvious place for this is inside `respond_to_connection_request` — check both profiles as
-- the couple is created, flag it there. That misses most of the cases it exists for:
--
--   * RevenueCat's webhook is asynchronous. Someone who subscribes and pairs in the same minute
--     may not have `subscription_active` written yet when the couple row is inserted.
--   * The overlap can begin long after pairing — a paired couple where one partner is subscribed,
--     and the other subscribes too without realising it was already covered.
--   * A subscription lapses and the condition resolves itself. A flag written once at accept
--     would still be sitting there.
--
-- So it is a query over current state, asked whenever the app wants to know, and it stops being
-- true on its own the moment either subscription ends.

-- ---------------------------------------------------------------------------
-- When the current subscription was first bought
-- ---------------------------------------------------------------------------
--
-- Null for everyone until the webhook next hears from RevenueCat about them, and null forever for
-- anyone whose entitlement carries no original purchase date. Both are handled the same way
-- downstream: with no date there is no way to tell who subscribed last, and the honest answer is
-- to say the two of them are doubled up without naming one of them.
alter table public.profiles
  add column if not exists subscription_started_at timestamptz;

comment on column public.profiles.subscription_started_at is
  'When this profile''s current subscription was originally purchased, per RevenueCat. Written '
  'only by the revenuecat-webhook function. Used to decide which partner of two subscribers is '
  'the redundant one — the later purchase.';

-- ---------------------------------------------------------------------------
-- Locked from the client, like the three columns beside it
-- ---------------------------------------------------------------------------
--
-- 20260915000000 took `subscription_active`, `subscription_tier` and `subscription_checked_at`
-- away from clients with a BEFORE trigger, because writing them was a paywall bypass. This column
-- is not a bypass — it grants nothing — but it decides which of two people is asked to stop
-- paying, and a client that could write it could nominate their partner. It joins the list.
--
-- Recreated in full rather than patched, since the original is a single `create or replace`.
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
    then
      raise exception 'subscription_active, subscription_tier, subscription_checked_at and subscription_started_at are set by the subscription webhook, not by the client'
        using errcode = '42501';
    end if;
    return new;
  end if;

  if new.subscription_active is distinct from old.subscription_active
    or new.subscription_tier is distinct from old.subscription_tier
    or new.subscription_checked_at is distinct from old.subscription_checked_at
    or new.subscription_started_at is distinct from old.subscription_started_at
  then
    raise exception 'subscription_active, subscription_tier, subscription_checked_at and subscription_started_at are set by the subscription webhook, not by the client'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Who, if anyone, is paying for nothing
-- ---------------------------------------------------------------------------
--
-- Answers for the caller's own couple only. Always returns a row, so the app can tell "there is no
-- overlap" apart from "the lookup failed".
--
--   both_subscribed        — the condition itself. False and everything else is null.
--   redundant_profile_id   — who should cancel, or null when the two purchase dates can't be
--                            compared (either is missing, or they are identical). Null means "we
--                            know you're doubled up but not which of you bought last", which the
--                            app has to be able to say without naming someone.
--   i_am_redundant         — whether that is the caller. The one field the banner branches on.
--
-- `security definer` because it reads the partner's subscription columns, which RLS on `profiles`
-- does expose to a partner today — but reading them here rather than in the client also keeps the
-- comparison in one place, and means the app never has to fetch two subscription records to make
-- a decision about one of them.
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

  if not (coalesce(v_a.subscription_active, false) and coalesce(v_b.subscription_active, false)) then
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

revoke all on function public.redundant_subscription() from public;
grant execute on function public.redundant_subscription() to authenticated;

comment on function public.redundant_subscription() is
  'Whether the caller''s couple holds two subscriptions where one would do, and which partner '
  'bought later. Never changes entitlement — this is only what the app needs to tell someone they '
  'can cancel.';
