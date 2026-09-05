-- ---------------------------------------------------------------------------
-- subscription_events: why is this couple Premium?
-- ---------------------------------------------------------------------------
--
-- `fetchSubscriptionActive` returns true if EITHER partner's profile says so, and
-- `private.couple_effective_tier` does the same for the tier. That is deliberate — "your partner
-- doesn't pay anything" is the product — but it means the answer to "why does this couple have
-- Premium?" is a disjunction over two rows, and neither row records where its value came from.
-- Today the honest answer to a support question is a shrug and a guess.
--
-- This does not change the OR, and does not change any read. It is an append-only record of what
-- the RevenueCat webhook decided and when, so the question becomes one query over both profiles
-- instead of inference. The alternative — moving entitlement onto `couples` so there is one row and
-- one writer — is architecturally cleaner and was deliberately not done: it needs a backfill, a
-- rewrite of every reader, and an answer to what happens to a couple's entitlement when they
-- dissolve and each person leaves with their own subscription. That is a lot of migration for a
-- two-person unit.
--
-- WRITTEN ONLY BY THE WEBHOOK, under the service role. RLS is on with NO policies, matching
-- `invite_redemption_attempts` and `rate_limit_events`: `authenticated` and `anon` can reach
-- nothing here. That is deliberate rather than lazy — this is a ledger about someone's paid status,
-- read by support and by whoever is debugging, and there is no screen that needs it.
--
-- Uniqueness is on (event_id, profile_id), NOT on event_id alone. A redelivered webhook must record
-- once rather than twice — RevenueCat retries, and duplicates would make the history lie about how
-- often something happened — but one event legitimately describes two profiles: a TRANSFER names
-- both the losing and the gaining account, and an alias resolves to the same person twice. Keying
-- on event_id alone would silently drop the second row, which is precisely the row someone
-- investigating a transfer needs. The webhook treats the conflict as success, since a redelivery
-- genuinely is nothing new.
--
-- Deliberately NOT a foreign key to `profiles`: the point of a ledger is to survive the row it
-- describes. An account deleted under `delete_own_account` should leave its billing history intact
-- for the period it was paying, and a cascade would erase exactly the record someone later needs.

create table public.subscription_events (
  id uuid primary key default gen_random_uuid(),
  -- No FK, on purpose — see above.
  profile_id uuid not null,
  -- RevenueCat's own event id, when it sent one. Null for a state we resolved without an event to
  -- attribute it to, which the unique index below tolerates.
  event_id text,
  event_type text,
  -- What the webhook resolved and wrote. `tier` is null when the subscription is not active, which
  -- is how `profiles.subscription_active` is derived, so the two cannot disagree.
  tier text check (tier is null or tier in ('plus', 'premium')),
  -- Whether the profile row actually changed. A 'stale' outcome means a newer reading had already
  -- landed and the freshness guard refused this one — worth recording, because a run of them is how
  -- out-of-order delivery looks from the outside.
  outcome text not null check (outcome in ('written', 'stale', 'no_profile')),
  -- RevenueCat's `request_date`, not ours: the same clock the freshness guard compares against.
  state_as_of timestamptz,
  recorded_at timestamptz not null default now()
);

create index subscription_events_profile_idx
  on public.subscription_events (profile_id, recorded_at desc);

-- Partial, because `event_id` is null for a state resolved without an event to attribute it to, and
-- those must not collide with each other.
create unique index subscription_events_event_profile_key
  on public.subscription_events (event_id, profile_id)
  where event_id is not null;

alter table public.subscription_events enable row level security;

comment on table public.subscription_events is
  'Append-only record of what the RevenueCat webhook decided for each profile. Answers "why is this '
  'couple Premium?", which the OR across both partners otherwise makes a guess. Service role only.';
