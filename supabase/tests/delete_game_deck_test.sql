-- ---------------------------------------------------------------------------
-- delete_game_deck: a deck takes its questions with it
-- ---------------------------------------------------------------------------
--
-- Deleting a deck used to be impossible rather than merely messy: every deck_id is a NO ACTION
-- foreign key, so a deck with a single question in it refused to go. The point of this RPC is
-- that one call clears the deck, its questions and the sessions played from it, together.
--
-- The assertions that matter are the two ends of "together": nothing belonging to the deck is
-- left behind (a survivor puts the FK back in the way next time), and nothing that merely sits
-- in the same table is touched — a deck delete must not reach into the shared content pool that
-- start_game_session draws from.

begin;
select plan(9);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-9191-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin@deckdelete.test', 'x', now(), now(), now()),
  ('bbbbbbbb-9191-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'partner@deckdelete.test', 'x', now(), now(), now()),
  ('cccccccc-9191-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'nobody@deckdelete.test', 'x', now(), now(), now());

insert into public.feedback_admins (profile_id) values ('aaaaaaaa-9191-0000-0000-000000000001')
on conflict do nothing;

insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active)
values ('dddddddd-9191-0000-0000-00000000000d', 'Test Topic', 'deep_conversations', 'Doomed Deck', '🗑️', 'plus', 0, true);

insert into public.deep_conversation_topics (id, topic, category, deck_id, active)
values
  ('11111111-9191-0000-0000-000000000001', 'A question in the deck', 'Test', 'dddddddd-9191-0000-0000-00000000000d', true),
  ('22222222-9191-0000-0000-000000000002', 'Another question in the deck', 'Test', 'dddddddd-9191-0000-0000-00000000000d', true);

-- The control: a row in the same table that belongs to no deck. It is what the shared pool is
-- made of, and it must survive.
insert into public.deep_conversation_topics (id, topic, category, deck_id, active)
values ('33333333-9191-0000-0000-000000000003', 'A question in no deck at all', 'Test', null, true);

-- A couple who actually played the deck, down to a recorded answer — the FK that blocks the
-- delete second, after the questions.
insert into public.couples (id, partner_a_id, partner_b_id, status)
values ('eeeeeeee-9191-0000-0000-00000000000e',
        'aaaaaaaa-9191-0000-0000-000000000001',
        'bbbbbbbb-9191-0000-0000-000000000002',
        'active');

insert into public.game_sessions (id, couple_id, game_type, initiator_id, deck_id, total_rounds)
values ('ffffffff-9191-0000-0000-00000000000f', 'eeeeeeee-9191-0000-0000-00000000000e', 'deep_conversations',
        'aaaaaaaa-9191-0000-0000-000000000001', 'dddddddd-9191-0000-0000-00000000000d', 2);

insert into public.game_session_rounds (session_id, round_number, content_id)
values
  ('ffffffff-9191-0000-0000-00000000000f', 1, '11111111-9191-0000-0000-000000000001'),
  ('ffffffff-9191-0000-0000-00000000000f', 2, '22222222-9191-0000-0000-000000000002');

insert into public.game_responses (session_id, round_number, responder_id, answer)
values ('ffffffff-9191-0000-0000-00000000000f', 1, 'aaaaaaaa-9191-0000-0000-000000000001', '"said something"'::jsonb);

-- ---------------------------------------------------------------------------
-- A signed-in non-admin
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-9191-0000-0000-000000000003","role":"authenticated"}';

select throws_ok(
  $$select public.delete_game_deck('dddddddd-9191-0000-0000-00000000000d')$$,
  '42501',
  null,
  'a signed-in non-admin cannot delete a deck'
);

select is(
  (select count(*)::int from public.deep_conversation_topics where deck_id = 'dddddddd-9191-0000-0000-00000000000d'),
  2,
  'and the refusal deleted nothing on its way out'
);

-- ---------------------------------------------------------------------------
-- The admin
-- ---------------------------------------------------------------------------

set local request.jwt.claims = '{"sub":"aaaaaaaa-9191-0000-0000-000000000001","role":"authenticated"}';

select throws_ok(
  $$select public.delete_game_deck('00000000-9191-0000-0000-000000000000')$$,
  'P0002',
  null,
  'deleting a deck that does not exist says so rather than silently succeeding'
);

select set_config('test.result', public.delete_game_deck('dddddddd-9191-0000-0000-00000000000d')::text, true);

select is(
  (current_setting('test.result')::json->>'questions_deleted')::int,
  2,
  'the call reports the two questions it deleted'
);

select is(
  (current_setting('test.result')::json->>'sessions_deleted')::int,
  1,
  'and the one session that had been played from the deck'
);

select is(
  (select count(*)::int from public.game_decks where id = 'dddddddd-9191-0000-0000-00000000000d'),
  0,
  'the deck is gone'
);

select is(
  (select count(*)::int from public.deep_conversation_topics where deck_id = 'dddddddd-9191-0000-0000-00000000000d'),
  0,
  'its questions are gone with it'
);

-- Rounds and responses cascade from game_sessions; if they did not, the next delete of a
-- like-named deck would be blocked by rows nobody can see from the admin UI.
select is(
  (select count(*)::int from public.game_session_rounds where session_id = 'ffffffff-9191-0000-0000-00000000000f'),
  0,
  'and the rounds of the deleted session went too'
);

select is(
  (select count(*)::int from public.deep_conversation_topics where id = '33333333-9191-0000-0000-000000000003'),
  1,
  'the deckless question in the shared pool is untouched'
);

select * from finish();
rollback;
