-- start_deck_session for someone playing alone: `subscription_active` decides Premium, not the tier
-- column, which is never cleared when a subscription lapses. See 20261114002100.

begin;
select plan(7);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-8181-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'lapsed@solodeck.test', 'x', now(), now(), now()),
  ('bbbbbbbb-8181-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'prem@solodeck.test', 'x', now(), now(), now());

-- Written as postgres: clients cannot set these (20260915000000).
update public.profiles set subscription_active = false, subscription_tier = 'premium'
  where id = 'aaaaaaaa-8181-0000-0000-000000000001';
update public.profiles set subscription_active = true, subscription_tier = 'premium'
  where id = 'bbbbbbbb-8181-0000-0000-000000000002';

-- Any premium and any plus deck a solo player may start (not Who's More Likely, which needs a
-- partner; not 18+, which needs a couple), and that has content. Kept in settings rather than a temp
-- table so they survive the role switch below.
select set_config('test.premium_deck', (
  select d.id::text from public.game_decks d
  where d.active and d.tier = 'premium' and not d.adult and d.game_type = 'deep_conversations'
    and exists (select 1 from public.deep_conversation_topics t where t.deck_id = d.id and t.active)
  order by d.sort_order limit 1), true);
select set_config('test.plus_deck', (
  select d.id::text from public.game_decks d
  where d.active and d.tier = 'plus' and not d.adult and d.game_type = 'deep_conversations'
    and exists (select 1 from public.deep_conversation_topics t where t.deck_id = d.id and t.active)
  order by d.sort_order limit 1), true);

select ok(
  current_setting('test.premium_deck', true) is not null and current_setting('test.plus_deck', true) is not null,
  'fixtures: a premium and a plus conversation deck exist'
);

set local role authenticated;

-- The lapsed solo player.
set local request.jwt.claims = '{"sub":"aaaaaaaa-8181-0000-0000-000000000001","role":"authenticated"}';

select throws_ok(
  format('select public.start_deck_session(%L::uuid)', current_setting('test.premium_deck')),
  'P0001', 'This deck requires Premium',
  'a lapsed solo player cannot start a premium deck on a leftover tier column'
);

select lives_ok(
  format('select public.start_deck_session(%L::uuid)', current_setting('test.plus_deck')),
  'and can still start a plus deck'
);

-- An active Premium solo player is unaffected.
set local request.jwt.claims = '{"sub":"bbbbbbbb-8181-0000-0000-000000000002","role":"authenticated"}';

select lives_ok(
  format('select public.start_deck_session(%L::uuid)', current_setting('test.premium_deck')),
  'an active Premium solo player starts the premium deck'
);

-- No session, no caller.
set local request.jwt.claims = '{"role":"authenticated"}';
select throws_ok(
  format('select public.start_deck_session(%L::uuid)', current_setting('test.plus_deck')),
  '42501', null,
  'a caller with no user id is refused before any lookup'
);

reset role;

select is(
  (select count(*)::int from public.game_sessions
    where initiator_id = 'aaaaaaaa-8181-0000-0000-000000000001'
      and deck_id = current_setting('test.premium_deck')::uuid),
  0,
  'no premium session was created for the lapsed player'
);

select ok(
  not has_function_privilege('anon', 'public.start_deck_session(uuid)', 'execute'),
  'anon cannot execute start_deck_session'
);

select * from finish();
rollback;
