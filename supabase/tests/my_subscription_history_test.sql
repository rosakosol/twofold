-- What the account page may say about a subscription that has ended.
--
-- The interesting cases are all the ones where a naive reading gives a wrong date:
--
--   * A null-tier event BEFORE the subscription is not an ending. Somebody whose first webhook
--     resolved nothing, then subscribed, has a null-tier row older than their purchase; reading
--     "the most recent null-tier event" would be right by accident here and wrong the moment the
--     order differs, so the ending is defined as the first null AFTER the last paid reading.
--   * A 'stale' event is a reading the freshness guard refused. It never described the account, so
--     it can neither prove a subscription nor date its end.
--   * Resubscribing moves the answer back to "no ending yet" — the last paid reading is newer than
--     the off-event, so there is nothing after it.
--   * Somebody who never subscribed gets ever_subscribed false, not a null date that a caller
--     might render as "ended, we don't know when".
--   * Subscribed once with no off-event recorded is ever_subscribed true and ended_at null, which
--     is the case a caller MUST render rather than assume a date for — every lapse predating
--     20260926000000 looks like this.

begin;
select plan(11);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-7777-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'lapsed@hist.test', 'x', now(), now(), now()),
  ('bbbbbbbb-7777-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'never@hist.test', 'x', now(), now(), now()),
  ('cccccccc-7777-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'again@hist.test', 'x', now(), now(), now()),
  ('dddddddd-7777-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'nooff@hist.test', 'x', now(), now(), now()),
  ('eeeeeeee-7777-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'stale@hist.test', 'x', now(), now(), now());

insert into public.profiles (id, first_name) values
  ('aaaaaaaa-7777-0000-0000-000000000001', 'Lapsed'),
  ('bbbbbbbb-7777-0000-0000-000000000002', 'Never'),
  ('cccccccc-7777-0000-0000-000000000003', 'Again'),
  ('dddddddd-7777-0000-0000-000000000004', 'NoOff'),
  ('eeeeeeee-7777-0000-0000-000000000005', 'Stale')
on conflict (id) do update set first_name = excluded.first_name;

-- Lapsed: a null reading before anything was bought, then Plus, then off.
insert into public.subscription_events (profile_id, event_id, event_type, tier, outcome, state_as_of)
values
  ('aaaaaaaa-7777-0000-0000-000000000001', 'a-0', 'INITIAL_PURCHASE', null,   'written', '2026-01-01T00:00:00Z'),
  ('aaaaaaaa-7777-0000-0000-000000000001', 'a-1', 'INITIAL_PURCHASE', 'plus', 'written', '2026-02-01T00:00:00Z'),
  ('aaaaaaaa-7777-0000-0000-000000000001', 'a-2', 'EXPIRATION',       null,   'written', '2026-06-15T00:00:00Z'),
  -- A later null reading as well: the ending is the FIRST one after the purchase, not the last.
  ('aaaaaaaa-7777-0000-0000-000000000001', 'a-3', 'EXPIRATION',       null,   'written', '2026-09-01T00:00:00Z');

-- Again: lapsed, then came back. Nothing has ended as of now.
insert into public.subscription_events (profile_id, event_id, event_type, tier, outcome, state_as_of)
values
  ('cccccccc-7777-0000-0000-000000000003', 'c-1', 'INITIAL_PURCHASE', 'plus',    'written', '2026-02-01T00:00:00Z'),
  ('cccccccc-7777-0000-0000-000000000003', 'c-2', 'EXPIRATION',       null,      'written', '2026-03-01T00:00:00Z'),
  ('cccccccc-7777-0000-0000-000000000003', 'c-3', 'INITIAL_PURCHASE', 'premium', 'written', '2026-04-01T00:00:00Z');

-- NoOff: bought, and no off-event was ever recorded.
insert into public.subscription_events (profile_id, event_id, event_type, tier, outcome, state_as_of)
values
  ('dddddddd-7777-0000-0000-000000000004', 'd-1', 'INITIAL_PURCHASE', 'premium', 'written', '2026-02-01T00:00:00Z');

-- Stale: every row was refused by the freshness guard, so none of them described the account.
insert into public.subscription_events (profile_id, event_id, event_type, tier, outcome, state_as_of)
values
  ('eeeeeeee-7777-0000-0000-000000000005', 'e-1', 'INITIAL_PURCHASE', 'plus', 'stale',      '2026-02-01T00:00:00Z'),
  ('eeeeeeee-7777-0000-0000-000000000005', 'e-2', 'EXPIRATION',       null,   'no_profile', '2026-03-01T00:00:00Z');

-- MARK: a lapsed subscriber gets the tier they had and the date it stopped

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-7777-0000-0000-000000000001"}';

select is(
  (public.my_subscription_history() ->> 'ever_subscribed')::boolean,
  true,
  'a lapsed subscriber is known to have subscribed, though their profile no longer says so'
);

select is(
  public.my_subscription_history() ->> 'last_tier',
  'plus',
  'and which tier it was, which profiles.subscription_tier was cleared of on lapse'
);

select is(
  (public.my_subscription_history() ->> 'ended_at')::timestamptz,
  '2026-06-15T00:00:00Z'::timestamptz,
  'the ending is the first null reading after the purchase, not the newest null reading'
);

-- MARK: never subscribed is not "ended on an unknown date"

set local request.jwt.claims = '{"sub":"bbbbbbbb-7777-0000-0000-000000000002"}';

select is(
  (public.my_subscription_history() ->> 'ever_subscribed')::boolean,
  false,
  'somebody with no events at all never subscribed'
);

select is(
  public.my_subscription_history() ->> 'ended_at',
  null,
  'and has no ending, so nothing invites the caller to say one lapsed'
);

-- MARK: resubscribing clears the ending

set local request.jwt.claims = '{"sub":"cccccccc-7777-0000-0000-000000000003"}';

select is(
  public.my_subscription_history() ->> 'last_tier',
  'premium',
  'coming back on a different tier reports the tier held now, not the one lost'
);

select is(
  public.my_subscription_history() ->> 'ended_at',
  null,
  'and no ending, because the newest paid reading is after the off-event'
);

-- MARK: subscribed, ending never recorded

set local request.jwt.claims = '{"sub":"dddddddd-7777-0000-0000-000000000004"}';

select is(
  (public.my_subscription_history() ->> 'ever_subscribed')::boolean,
  true,
  'a subscription with no off-event is still known to have existed'
);

select is(
  public.my_subscription_history() ->> 'ended_at',
  null,
  'with a null date rather than a guessed one — the caller has to render this case'
);

-- MARK: a refused reading proves nothing

set local request.jwt.claims = '{"sub":"eeeeeeee-7777-0000-0000-000000000005"}';

select is(
  (public.my_subscription_history() ->> 'ever_subscribed')::boolean,
  false,
  'a stale reading never described the account, so it cannot prove a subscription'
);

-- MARK: the table stays shut, so the function is the only way in
--
-- Zero rows rather than an error, which is what RLS with no policies actually does: the table-level
-- SELECT grant from 20260911000100 is still there, so the read is permitted and then filtered to
-- nothing. Asserted as the lapsed user, who has four rows of their own — proving the log is closed
-- even to the person it is about, which is the reason my_subscription_history() is security definer.

set local request.jwt.claims = '{"sub":"aaaaaaaa-7777-0000-0000-000000000001"}';

select is(
  (select count(*)::int from public.subscription_events),
  0,
  'the log is unreadable even to the person whose events they are'
);

select * from finish();
rollback;
