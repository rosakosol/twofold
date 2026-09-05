-- ---------------------------------------------------------------------------
-- subscription_events: a ledger clients cannot see or touch
-- ---------------------------------------------------------------------------
--
-- Entitlement is read as an OR across both partners' profiles, so "why is this couple Premium?" is
-- otherwise a guess. This table records what the RevenueCat webhook decided; it changes no read and
-- no behaviour, so what is worth pinning is its shape and its reach.
--
-- The uniqueness rule is the subtle one. A redelivery must record once, but ONE event legitimately
-- describes TWO profiles — a TRANSFER names both the losing and the gaining account. Keying on
-- event_id alone would silently drop the second row, which is exactly the row someone investigating
-- a transfer needs.

begin;
select plan(7);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-1515-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@subevents.test', 'x', now(), now(), now()),
  ('bbbbbbbb-1515-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@subevents.test', 'x', now(), now(), now());

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.subscription_events (profile_id, event_id, event_type, tier, outcome, state_as_of)
    values ('aaaaaaaa-1515-0000-0000-000000000001', 'evt_transfer_1', 'TRANSFER', 'premium', 'written', now())$$,
  'the webhook can record a decision'
);

-- The same event, the other side of a transfer. This must be allowed.
select lives_ok(
  $$insert into public.subscription_events (profile_id, event_id, event_type, tier, outcome, state_as_of)
    values ('bbbbbbbb-1515-0000-0000-000000000002', 'evt_transfer_1', 'TRANSFER', null, 'written', now())$$,
  'one event can describe two profiles — a transfer names both accounts'
);

-- A redelivery of that event for the same profile must not double-count.
select throws_ok(
  $$insert into public.subscription_events (profile_id, event_id, event_type, tier, outcome, state_as_of)
    values ('aaaaaaaa-1515-0000-0000-000000000001', 'evt_transfer_1', 'TRANSFER', 'premium', 'written', now())$$,
  '23505',
  null,
  'but the same event for the same profile is refused — a redelivery records once'
);

-- Null event ids are for states resolved without an event to attribute them to, and several of
-- those for one profile are legitimate. The unique index is partial for this reason.
select lives_ok(
  $$insert into public.subscription_events (profile_id, event_id, event_type, tier, outcome)
    values ('aaaaaaaa-1515-0000-0000-000000000001', null, 'RENEWAL', 'premium', 'stale'),
           ('aaaaaaaa-1515-0000-0000-000000000001', null, 'RENEWAL', 'premium', 'stale')$$,
  'rows with no event id do not collide with each other'
);

select throws_ok(
  $$insert into public.subscription_events (profile_id, outcome, tier)
    values ('aaaaaaaa-1515-0000-0000-000000000001', 'written', 'gold')$$,
  '23514',
  null,
  'an unknown tier is refused — the ledger cannot disagree with the check constraint on profiles'
);

-- ---------------------------------------------------------------------------
-- Reach
-- ---------------------------------------------------------------------------
--
-- RLS is on with no policies, matching invite_redemption_attempts and rate_limit_events. This is a
-- record of someone's paid status; no screen needs it and no client should see it.

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-1515-0000-0000-000000000001","role":"authenticated"}';

select is(
  (select count(*)::int from public.subscription_events),
  0,
  'a signed-in user cannot read the ledger, not even their own rows'
);

select throws_ok(
  $$insert into public.subscription_events (profile_id, outcome)
    values ('aaaaaaaa-1515-0000-0000-000000000001', 'written')$$,
  '42501',
  null,
  'nor write to it — the webhook under the service role is the only writer'
);

select * from finish();
rollback;
