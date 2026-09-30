-- ---------------------------------------------------------------------------
-- Whether the caller ever subscribed, and when it ended
-- ---------------------------------------------------------------------------
--
-- The account page has been telling anybody without a live subscription that they are "on the free
-- plan". There is no such plan. A person is subscribed or they are not, and describing "not" as a
-- product invents a tier nobody sells, nobody can be on, and nobody chose — while burying the one
-- fact that is actually useful to somebody staring at that card: their subscription ran out, and
-- when.
--
-- `profiles` cannot answer it. `revenuecat-webhook` writes `subscription_tier` and
-- `subscription_started_at` as null the moment a subscription lapses — deliberately, so a stale
-- start date cannot outlive the subscription it belonged to. The row that results is
-- indistinguishable from somebody who has never paid for anything.
--
-- `subscription_events` (20260926000000) does have it. It is append-only, it records the tier the
-- webhook resolved for every decision, and it exists precisely so "why is this couple Premium?"
-- has an answer rather than a guess. This reads the same log backwards.
--
-- ---------------------------------------------------------------------------
-- Why security definer
-- ---------------------------------------------------------------------------
--
-- That table is service-role only: RLS is on and it has no policies, so the account page — which
-- runs as the signed-in user, under the same RLS as every other client, and has no service role
-- anywhere in it — cannot read a row of it. Rather than open the table up, this exposes the two
-- facts a person may know about their own billing and nothing else: whether they ever held a
-- subscription, which tier it was, and when it stopped. No event ids, no store, no counts, no
-- other profile.
--
-- Keyed off auth.uid() with no session check of its own, the same shape as my_admin_roles(): an
-- anonymous caller is not an error to be raised at, it is a question whose answer is "never".
--
-- ---------------------------------------------------------------------------
-- What "ended" means here
-- ---------------------------------------------------------------------------
--
-- The last event that resolved a tier, then the first event after it that resolved none. Not
-- simply "the most recent null-tier event": a trial that was refused, or a webhook arriving for
-- somebody who has never subscribed, writes a null tier too, and reading that as an ending would
-- date a lapse for a person who never lapsed.
--
-- Only 'written' outcomes count. A 'stale' row is a reading the freshness guard refused because a
-- newer one had already landed, so it never described the account's state, and 'no_profile' never
-- touched an account at all.
--
-- `state_as_of` before `recorded_at`: the first is RevenueCat's own clock for when the state was
-- true, the second is when we happened to hear about it. They are usually close and occasionally
-- are not, and the honest date is the one the subscription actually ended on.
--
-- `ended_at` can be null while `ever_subscribed` is true, and the caller must render that case
-- rather than assume a date. Two ways to reach it: anybody who lapsed before 20260926000000
-- created this log has no off-event to find, and `reconcile-subscriptions` can correct a profile
-- without an event to attribute it to. "You had a subscription and we cannot say exactly when it
-- ended" is a true sentence; a guessed date is not.

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
    select coalesce(e.state_as_of, e.recorded_at) as at
    from public.subscription_events e, paid
    where e.profile_id = auth.uid()
      and e.outcome = 'written'
      and e.tier is null
      and coalesce(e.state_as_of, e.recorded_at) > paid.at
    order by coalesce(e.state_as_of, e.recorded_at) asc
    limit 1
  )
  select jsonb_build_object(
    'ever_subscribed', exists (select 1 from paid),
    'last_tier', (select tier from paid),
    'ended_at', (select at from ended)
  );
$$;

comment on function public.my_subscription_history() is
  'Whether the calling user ever held a subscription, which tier it last was, and when it ended, '
  'as {ever_subscribed, last_tier, ended_at}. Reads subscription_events, which is service-role '
  'only, and returns nothing else from it. ended_at is null when the ending was never recorded — '
  'a lapse predating 20260926000000, or a reconcile with no event behind it — so a caller must '
  'handle "subscribed once, end date unknown". Returns ever_subscribed false for an anonymous '
  'caller rather than raising.';

grant execute on function public.my_subscription_history() to anon, authenticated;
