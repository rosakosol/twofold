-- ---------------------------------------------------------------------------
-- A plus couple can play every card in a plus deck
-- ---------------------------------------------------------------------------
--
-- Reported: a new Plus couple opened decks they had never played and landed on "you've finished".
-- 20 plus decks held premium cards (20260726000000 filled them from the shared pool by category,
-- not tier), and the content policies hide premium cards below premium. The session's rounds
-- pointed at cards the couple could not read, and with no card to draw the app showed the
-- finished screen.
--
-- Pinned two ways: the data no longer holds such a card, and it cannot be made to again.
-- 20261113001500 made a card's tier follow its deck's, so the mis-tagging this test used to
-- re-create on purpose is now overwritten as it happens: the plus couple gets every card, and a
-- deck whose cards were all set to premium still starts. Before that, this checked that
-- start_deck_session left such cards out, which was the workaround for a state that can no longer
-- arise.

begin;
select plan(6);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-1313-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'plusa@decktier.test', 'x', now(), now(), now()),
  ('bbbbbbbb-1313-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'plusb@decktier.test', 'x', now(), now(), now()),
  ('cccccccc-1313-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'prema@decktier.test', 'x', now(), now(), now()),
  ('dddddddd-1313-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'premb@decktier.test', 'x', now(), now(), now());

-- Shaped like the report: one partner subscribed, the other not.
update public.profiles set subscription_active = true, subscription_tier = 'plus'
  where id = 'aaaaaaaa-1313-0000-0000-000000000001';
update public.profiles set subscription_active = true, subscription_tier = 'premium'
  where id = 'cccccccc-1313-0000-0000-000000000003';

insert into public.couples (id, partner_a_id, partner_b_id, status) values
  ('eeeeeeee-1313-0000-0000-000000000005', 'aaaaaaaa-1313-0000-0000-000000000001', 'bbbbbbbb-1313-0000-0000-000000000002', 'active'),
  ('ffffffff-1313-0000-0000-000000000006', 'cccccccc-1313-0000-0000-000000000003', 'dddddddd-1313-0000-0000-000000000004', 'active');

select is(
  (select count(*)::int from (
     select deck_id, tier from public.trivia_questions where active
     union all select deck_id, tier from public.more_likely_prompts where active
     union all select deck_id, tier from public.this_or_that_prompts where active
     union all select deck_id, tier from public.deep_conversation_topics where active) c
   join public.game_decks d on d.id = c.deck_id and d.active
   where d.tier = 'plus' and c.tier = 'premium'),
  0,
  'no active plus deck holds a premium card'
);

-- Two plus decks, re-broken on purpose: one with a single premium card, one with nothing else.
-- Neither sticks (see the header), which is what the checks below are about.
select set_config('test.mixed', (
  select d.id::text from public.game_decks d
  where d.tier = 'plus' and d.active and d.game_type = 'this_or_that'
    and (select count(*) from public.this_or_that_prompts p where p.deck_id = d.id and p.active) >= 2
  order by d.id limit 1
), true);
select set_config('test.mixed_cards', (
  select count(*)::text from public.this_or_that_prompts where deck_id = current_setting('test.mixed')::uuid and active
), true);
update public.this_or_that_prompts set tier = 'premium'
  where id = (select id from public.this_or_that_prompts
              where deck_id = current_setting('test.mixed')::uuid and active order by id limit 1);

select set_config('test.all_premium', (
  select d.id::text from public.game_decks d
  where d.tier = 'plus' and d.active and d.game_type = 'this_or_that'
    and d.id <> current_setting('test.mixed')::uuid
    and exists (select 1 from public.this_or_that_prompts p where p.deck_id = d.id and p.active)
  order by d.id limit 1
), true);
update public.this_or_that_prompts set tier = 'premium'
  where deck_id = current_setting('test.all_premium')::uuid;

set local role authenticated;

-- ---------------------------------------------------------------------------
-- The plus couple
-- ---------------------------------------------------------------------------

set local request.jwt.claims = '{"sub":"bbbbbbbb-1313-0000-0000-000000000002","role":"authenticated"}';
select set_config('test.plus_session',
  public.start_deck_session(current_setting('test.mixed')::uuid)::text, true);

select is(
  (select total_rounds from public.game_sessions where id = current_setting('test.plus_session')::uuid),
  current_setting('test.mixed_cards')::int,
  'setting a plus deck''s card to premium does not stick: the plus couple gets every card'
);

-- The property the app depends on: every round has a card this player can read.
select is(
  (select count(*)::int from public.game_session_rounds r
   join public.this_or_that_prompts p on p.id = r.content_id
   where r.session_id = current_setting('test.plus_session')::uuid),
  (select total_rounds from public.game_sessions where id = current_setting('test.plus_session')::uuid),
  'and every round it built is one the plus partner can read'
);

select lives_ok(
  format('select public.start_deck_session(%L::uuid)', current_setting('test.all_premium')),
  'nor does setting all of them: the deck still starts for a plus couple'
);

-- ---------------------------------------------------------------------------
-- The premium couple
-- ---------------------------------------------------------------------------

set local request.jwt.claims = '{"sub":"dddddddd-1313-0000-0000-000000000004","role":"authenticated"}';
select set_config('test.premium_session',
  public.start_deck_session(current_setting('test.mixed')::uuid)::text, true);
select is(
  (select total_rounds from public.game_sessions where id = current_setting('test.premium_session')::uuid),
  current_setting('test.mixed_cards')::int,
  'a premium couple still gets every card in the deck'
);

select lives_ok(
  format('select public.start_deck_session(%L::uuid)', current_setting('test.all_premium')),
  'and so does a premium couple'
);

select * from finish();
rollback;
