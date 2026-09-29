-- Whether the active subscription is still in its free trial, so a screen can say what cancelling
-- will actually do.
--
-- Cancelling during a trial ends access immediately — there is no paid period to run out — while
-- cancelling a paid subscription leaves it running to the end of the period. Observed, not inferred:
-- a web subscription bought at 07:21 and cancelled at 07:57, thirty-six minutes into a fourteen-day
-- trial, came back `subscription_active = false`.
--
-- 20261111000000 made the copy cover both outcomes without knowing which applied, because nothing on
-- the row could tell them apart. That was honest and vague, and vague is a poor thing to be on a
-- confirmation dialog about losing access: the person reading it is deciding, and the sentence that
-- matters to them is the one about their own situation. This column is what lets the screen pick.
--
-- Same shape as `subscription_store` (20261109000500): written only by `revenuecat-webhook`, null
-- when unknown, and every consumer must treat null as "we do not know" rather than as false. The
-- asymmetry matters here too — reading null as "not a trial" tells a trialist they keep access they
-- are about to lose, which is the mistake this column exists to stop.

alter table public.profiles
  add column if not exists subscription_is_trial boolean;

comment on column public.profiles.subscription_is_trial is
  'True while the active subscription is in a free trial, as reported by RevenueCat''s '
  '`period_type` and written by revenuecat-webhook. Null means unknown — not yet seen by the '
  'webhook, or no subscription. Consumers must treat null as "do not know", never as false: '
  'cancelling during a trial ends access immediately, and telling a trialist otherwise costs them '
  'the rest of their trial.';

-- ---------------------------------------------------------------------------
-- Locked from clients, the way the other six are
-- ---------------------------------------------------------------------------
--
-- A new column gets no grant, because 20260915000000 removed the table-level UPDATE and re-granted
-- the harmless columns one at a time. That alone is not the guarantee: a single
-- `grant all on all tables in schema public` re-opens every column silently, and this repo has run
-- exactly that statement before. The trigger is what survives it, because a trigger is not a
-- privilege and no GRANT restores the write.
--
-- Rewritten in full from the CURRENT definition (20261109000500's, which added `subscription_store`
-- to 20261002000000's), not from the original in 20260915000000 — `create or replace function`
-- takes the whole body, so building on the wrong version silently drops whichever columns were added
-- in between. `subscription_columns_client_locked_test` catches that, and has.
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
      or new.subscription_is_trial is not null
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
    or new.subscription_is_trial is distinct from old.subscription_is_trial
  then
    raise exception 'the subscription columns are set by the subscription webhook, not by the client'
      using errcode = '42501';
  end if;

  return new;
end;
$$;
