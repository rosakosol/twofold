-- Two facts the account page cannot currently tell anybody about their own subscription: when the
-- next payment is, and why the last one stopped.
--
-- ---------------------------------------------------------------------------
-- profiles.subscription_expires_at
-- ---------------------------------------------------------------------------
--
-- The card can say "Twofold Premium since September 2026" and then nothing about what happens next.
-- Every other screen that touches this has had to talk around the missing date — "until the end of
-- the period you've already paid for" is that sentence, written four times, because the date itself
-- was not available to write.
--
-- It is the same value either way, which is why one column covers both readings. RevenueCat's
-- `expires_date` on the active entitlement is when the current period ends: with `will_renew` true
-- that is the next charge, and with it false that is when access stops. The webhook already fetches
-- the entitlement it comes from — `resolveStore` and `resolveIsTrial` read the same object.
--
-- No UPDATE grant, deliberately. 20260915000000 revoked table-level UPDATE on `profiles` from anon
-- and authenticated and re-granted about forty columns individually, so a column added now is one a
-- client cannot write — which is exactly right for a billing fact, and is why this migration adds a
-- grant for nothing. The service role keeps its table-level UPDATE and is the only writer. SELECT
-- is table-level and so covers the new column without being restated.
--
-- ---------------------------------------------------------------------------
-- subscription_events.expiration_reason
-- ---------------------------------------------------------------------------
--
-- "Cancelled" and "lapsed" are different things and the log could not tell them apart. Both arrive
-- as an EXPIRATION event with a null tier: somebody who chose to stop, and somebody whose card was
-- declined, look identical. Calling both "cancelled" tells the second person they did something
-- they did not do, and hides the one thing they might want to fix.
--
-- RevenueCat sends `expiration_reason` on that event. Recorded rather than resolved into a boolean,
-- because its values are not a binary — UNSUBSCRIBE, BILLING_ERROR, DEVELOPER_INITIATED,
-- PRICE_INCREASE, CUSTOMER_SUPPORT, UNKNOWN — and collapsing them at write time throws away the
-- distinction between "we know it was a refund" and "we do not know".
--
-- Nullable, and null for every row already in the table. That is the normal case for a while, not
-- an edge: the log itself only dates from 20260926000000, so `my_subscription_history` below falls
-- back to inferring from event types and then to saying nothing, and the client must render the
-- "ended, reason unknown" case.

alter table public.subscription_events
  add column if not exists expiration_reason text;

comment on column public.subscription_events.expiration_reason is
  'RevenueCat''s `expiration_reason` from an EXPIRATION event (UNSUBSCRIBE, BILLING_ERROR, '
  'DEVELOPER_INITIATED, PRICE_INCREASE, CUSTOMER_SUPPORT, UNKNOWN). Null on every other event type, '
  'and on every row written before this column existed. Stored raw: collapsing it at write time '
  'would lose the difference between a known reason and an unknown one.';

alter table public.profiles
  add column if not exists subscription_expires_at timestamptz;

comment on column public.profiles.subscription_expires_at is
  'When the current subscription period ends, from RevenueCat''s `expires_date` on the active '
  'entitlement. With subscription_will_renew true this is the next payment date; with it false it '
  'is when access stops. Null when there is no subscription, and cleared on lapse alongside '
  'subscription_tier so a stale date cannot outlive what it described. Written only by the service '
  'role — a client has no UPDATE grant on it, see 20260915000000.';

-- ---------------------------------------------------------------------------
-- my_subscription_history, now saying why
-- ---------------------------------------------------------------------------
--
-- Three sources, in order of how much they actually know:
--
--   1. The off-event's own `expiration_reason`. Authoritative when present.
--   2. The event types seen between the last paid reading and the ending. A CANCELLATION means the
--      person cancelled; a BILLING_ISSUE means a payment failed. This is what answers the question
--      for every lapse already recorded, since none of those rows carry a reason.
--   3. Nothing, so `ended_reason` is null and the caller says "ended" without a cause.
--
-- PRICE_INCREASE counts as cancelled: the subscription stopped because the person declined to
-- continue at a new price, which is a choice, not a failure. DEVELOPER_INITIATED and
-- CUSTOMER_SUPPORT are deliberately left unknown — they are refunds and revocations, and neither
-- "you cancelled" nor "your payment failed" is a true thing to tell somebody about one.

create or replace function public.my_subscription_history()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with paid as (
    select coalesce(state_as_of, recorded_at) as at, tier
    from public.subscription_events
    where profile_id = auth.uid()
      and outcome = 'written'
      and tier is not null
    order by coalesce(state_as_of, recorded_at) desc
    limit 1
  ),
  ended as (
    select coalesce(e.state_as_of, e.recorded_at) as at, e.expiration_reason
    from public.subscription_events e, paid
    where e.profile_id = auth.uid()
      and e.outcome = 'written'
      and e.tier is null
      and coalesce(e.state_as_of, e.recorded_at) > paid.at
    order by coalesce(e.state_as_of, e.recorded_at) asc
    limit 1
  ),
  -- Every event in the window, whatever its outcome. A CANCELLATION does not change the tier, so
  -- the webhook may well have recorded it as 'stale' against a newer reading — it is still
  -- evidence that RevenueCat saw a cancellation, which is all this is being asked.
  signals as (
    select
      bool_or(upper(coalesce(e.event_type, '')) = 'CANCELLATION') as cancelled,
      bool_or(upper(coalesce(e.event_type, '')) = 'BILLING_ISSUE') as billing_issue
    from public.subscription_events e, paid, ended
    where e.profile_id = auth.uid()
      and coalesce(e.state_as_of, e.recorded_at) >= paid.at
      and coalesce(e.state_as_of, e.recorded_at) <= ended.at
  )
  select jsonb_build_object(
    'ever_subscribed', exists (select 1 from paid),
    'last_tier', (select tier from paid),
    'ended_at', (select at from ended),
    'ended_reason', (
      select case
        when upper(coalesce(e.expiration_reason, '')) in ('UNSUBSCRIBE', 'PRICE_INCREASE') then 'cancelled'
        when upper(coalesce(e.expiration_reason, '')) = 'BILLING_ERROR' then 'lapsed'
        when (select billing_issue from signals) then 'lapsed'
        when (select cancelled from signals) then 'cancelled'
        else null
      end
      from ended e
    )
  );
$$;

comment on function public.my_subscription_history() is
  'Whether the calling user ever held a subscription, which tier it last was, when it ended and '
  'why, as {ever_subscribed, last_tier, ended_at, ended_reason}. ended_reason is ''cancelled'', '
  '''lapsed'' or null — null meaning the ending is known but its cause is not, which a caller must '
  'render rather than guess at. Reads subscription_events, which is service-role only, and returns '
  'nothing else from it. Returns ever_subscribed false for an anonymous caller rather than raising.';

grant execute on function public.my_subscription_history() to anon, authenticated;
