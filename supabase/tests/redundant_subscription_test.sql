-- Two subscriptions where one would do.
--
-- The property that matters is not "detects the overlap" — it is *who gets named*. Telling the
-- wrong partner to cancel costs them a subscription they meant to keep, so the interesting
-- assertions are the ones where the answer has to be "we can't tell": a missing purchase date, or
-- two identical ones.

begin;
select plan(13);

create extension if not exists pgtap;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values
  -- Subscribed first. Keeps their subscription.
  ('aaaaaaaa-2222-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'early@redundant.test', 'x', now(), now()),
  -- Subscribed later. The one to be told.
  ('aaaaaaaa-2222-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'late@redundant.test', 'x', now(), now()),
  ('aaaaaaaa-2222-0000-0000-00000000000e', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'solo@redundant.test', 'x', now(), now())
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- No couple at all
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-2222-0000-0000-00000000000e","role":"authenticated"}';

select is(
  (select both_subscribed from public.redundant_subscription()),
  false, 'someone with no partner is never doubled up'
);
select is(
  (select i_am_redundant from public.redundant_subscription()),
  false, 'and is never the one asked to cancel'
);

reset role;

insert into public.couples (id, partner_a_id, partner_b_id, status)
values ('cccccccc-2222-0000-0000-00000000000c',
        'aaaaaaaa-2222-0000-0000-00000000000a',
        'aaaaaaaa-2222-0000-0000-00000000000b',
        'active');

-- ---------------------------------------------------------------------------
-- Paired, one subscriber
-- ---------------------------------------------------------------------------

update public.profiles
set subscription_active = true,
    subscription_tier = 'plus',
    subscription_started_at = timestamptz '2026-01-01 00:00:00+00'
where id = 'aaaaaaaa-2222-0000-0000-00000000000a';

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-2222-0000-0000-00000000000a","role":"authenticated"}';

select is(
  (select both_subscribed from public.redundant_subscription()),
  false, 'one subscription between two people is not redundant — it is the normal case'
);

reset role;

-- ---------------------------------------------------------------------------
-- Both subscribed, both dates known
-- ---------------------------------------------------------------------------

update public.profiles
set subscription_active = true,
    subscription_tier = 'premium',
    subscription_started_at = timestamptz '2026-06-01 00:00:00+00'
where id = 'aaaaaaaa-2222-0000-0000-00000000000b';

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-2222-0000-0000-00000000000b","role":"authenticated"}';

select is(
  (select both_subscribed from public.redundant_subscription()),
  true, 'two active subscriptions in one couple is the condition'
);
select is(
  (select redundant_profile_id from public.redundant_subscription()),
  'aaaaaaaa-2222-0000-0000-00000000000b'::uuid,
  'the later purchase is the redundant one'
);
select is(
  (select i_am_redundant from public.redundant_subscription()),
  true, 'and the later purchaser is told it is them'
);

-- The same state, asked by the other partner. This is the assertion that fails if the answer is
-- computed relative to the caller rather than to the purchase dates.
set local request.jwt.claims = '{"sub":"aaaaaaaa-2222-0000-0000-00000000000a","role":"authenticated"}';

select is(
  (select redundant_profile_id from public.redundant_subscription()),
  'aaaaaaaa-2222-0000-0000-00000000000b'::uuid,
  'both partners are told the same person is redundant'
);
select is(
  (select i_am_redundant from public.redundant_subscription()),
  false, 'the earlier purchaser is not asked to cancel'
);

reset role;

-- ---------------------------------------------------------------------------
-- When it cannot be decided
-- ---------------------------------------------------------------------------
--
-- Both of these must still report the overlap. "You are both subscribed" is useful on its own;
-- naming the wrong person is not.

update public.profiles set subscription_started_at = null
where id = 'aaaaaaaa-2222-0000-0000-00000000000a';

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-2222-0000-0000-00000000000b","role":"authenticated"}';

select is(
  (select both_subscribed from public.redundant_subscription()),
  true, 'a missing purchase date does not hide the overlap'
);
select is(
  (select redundant_profile_id from public.redundant_subscription()),
  null::uuid, 'but nobody is named when one date is unknown'
);

reset role;

update public.profiles set subscription_started_at = timestamptz '2026-06-01 00:00:00+00'
where id = 'aaaaaaaa-2222-0000-0000-00000000000a';

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-2222-0000-0000-00000000000b","role":"authenticated"}';

select is(
  (select redundant_profile_id from public.redundant_subscription()),
  null::uuid, 'nor when the two bought at the same moment'
);

-- ---------------------------------------------------------------------------
-- The new column is the webhook's, like the three beside it
-- ---------------------------------------------------------------------------
--
-- Not an entitlement, so writing it grants nothing — but it decides which of two people is asked
-- to stop paying, and a client that could set it could nominate their partner.

select throws_ok(
  $$ update public.profiles set subscription_started_at = timestamptz '2000-01-01 00:00:00+00'
     where id = 'aaaaaaaa-2222-0000-0000-00000000000b' $$,
  '42501',
  null,
  'a client cannot backdate its own subscription to make its partner the redundant one'
);

reset role;

-- And still cannot with the column grant handed back.
--
-- The assertion above passes on either of two mechanisms, and a negative control showed it was
-- passing on the weaker one: 20260915000000 revoked table-level UPDATE on profiles and re-granted
-- the harmless columns one at a time, so a column added later has no grant and the write dies at
-- the privilege check without the trigger ever running. Deleting the trigger clause entirely broke
-- nothing.
--
-- That grant is exactly what 20260915000000's own comment says will come back: one
-- `grant all on all tables in schema public to authenticated` restores it in full, and that
-- statement is already in this repo's history as the fix for an unrelated outage. So the grant is
-- restored here, inside the transaction, and the refusal has to still hold — which is the trigger,
-- and only the trigger.
grant update (subscription_started_at) on public.profiles to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-2222-0000-0000-00000000000b","role":"authenticated"}';

select throws_ok(
  $$ update public.profiles set subscription_started_at = timestamptz '2000-01-01 00:00:00+00'
     where id = 'aaaaaaaa-2222-0000-0000-00000000000b' $$,
  '42501',
  null,
  'the trigger refuses it even when the column grant is restored'
);

reset role;

select * from finish();
rollback;
