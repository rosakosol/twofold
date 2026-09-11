-- Starting a Word Guess: the allowance, the resume, and the streak it must not touch.
--
-- Four things here are only wrong in ways nobody would see from the app:
--
--   * The allowance is per couple, not per person. Counted per person, a Plus couple gets two words
--     a day and compares two different boards, which is not the game.
--   * A solo session never reaches `completed` — `advance_game_session` waits for a second
--     responder who never comes — so a naive resume hands an unpaired player the same finished
--     board forever. That exact bug shipped in `start_sudoku_session` and is pinned here so this
--     game does not repeat it.
--   * `is_daily` must stay false. It drives the streak, and the streak belongs to the daily
--     conversation question alone. A word game feeding it would let a couple hold a long streak
--     having never once answered a question about each other.
--   * A lapsed Premium subscriber must fall back to the Plus allowance. `subscription_tier` is
--     never cleared on lapse, so reading it without `subscription_active` grants unlimited boards
--     to somebody who stopped paying — the mistake this codebase has already made once.

begin;
select plan(14);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-5555-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@word.test', 'x', now(), now(), now()),
  ('bbbbbbbb-5555-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@word.test', 'x', now(), now(), now()),
  ('dddddddd-5555-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'd@word.test', 'x', now(), now(), now()),
  ('eeeeeeee-5555-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'e@word.test', 'x', now(), now(), now());

insert into public.profiles (id, first_name, subscription_active, subscription_tier) values
  ('aaaaaaaa-5555-0000-0000-000000000001', 'Ada', true, 'plus'),
  ('bbbbbbbb-5555-0000-0000-000000000002', 'Mel', true, 'plus'),
  -- Solo, and lapsed: the tier still says premium because nothing ever clears it.
  ('dddddddd-5555-0000-0000-000000000004', 'Dev', false, 'premium'),
  ('eeeeeeee-5555-0000-0000-000000000005', 'Eve', true, 'premium')
on conflict (id) do update
  set first_name = excluded.first_name,
      subscription_active = excluded.subscription_active,
      subscription_tier = excluded.subscription_tier;

insert into public.couples (id, partner_a_id, partner_b_id)
values ('cccccccc-5555-0000-0000-000000000003', 'aaaaaaaa-5555-0000-0000-000000000001', 'bbbbbbbb-5555-0000-0000-000000000002');

-- MARK: a Plus couple gets one board a day, between the two of them

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-5555-0000-0000-000000000001"}';

select lives_ok(
  $$ select public.start_word_guess_session() $$,
  'a Plus couple can start their word of the day'
);

select is(
  (select count(*)::int from public.game_sessions where game_type = 'word_guess' and couple_id = 'cccccccc-5555-0000-0000-000000000003'),
  1,
  'one session exists'
);

select is(
  (select is_daily from public.game_sessions where game_type = 'word_guess' and couple_id = 'cccccccc-5555-0000-0000-000000000003'),
  false,
  'it is not a daily session, so it can never touch the streak'
);

select isnt(
  (select daily_local_date from public.game_sessions where game_type = 'word_guess' and couple_id = 'cccccccc-5555-0000-0000-000000000003'),
  null,
  'but it does record the local day it belongs to, which is what the allowance counts'
);

-- Asking again gives back the same board rather than a second one.
select is(
  (select (public.start_word_guess_session()).resumed),
  true,
  'asking again resumes the board in progress'
);

select is(
  (select count(*)::int from public.game_sessions where game_type = 'word_guess' and couple_id = 'cccccccc-5555-0000-0000-000000000003'),
  1,
  'and starts nothing new'
);

-- The partner gets the same board, which is the whole point: they compare one word.
set local request.jwt.claims = '{"sub":"bbbbbbbb-5555-0000-0000-000000000002"}';

select is(
  (select (public.start_word_guess_session()).resumed),
  true,
  'the partner is handed the same board, not one of their own'
);

-- MARK: the allowance bites once the board is finished

-- Finish it the way the app does: one response each, which completes the session.
set local role postgres;
insert into public.game_responses (session_id, round_number, responder_id, answer)
select gs.id, 1, 'aaaaaaaa-5555-0000-0000-000000000001', '{"value":"wordguess.v1|crane|60|1"}'
from public.game_sessions gs where gs.game_type = 'word_guess' and gs.couple_id = 'cccccccc-5555-0000-0000-000000000003';
insert into public.game_responses (session_id, round_number, responder_id, answer)
select gs.id, 1, 'bbbbbbbb-5555-0000-0000-000000000002', '{"value":"wordguess.v1|crane|90|1"}'
from public.game_sessions gs where gs.game_type = 'word_guess' and gs.couple_id = 'cccccccc-5555-0000-0000-000000000003';

select is(
  (select status::text from public.game_sessions where game_type = 'word_guess' and couple_id = 'cccccccc-5555-0000-0000-000000000003'),
  'completed',
  'both answering completes the session'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-5555-0000-0000-000000000001"}';

select throws_ok(
  $$ select public.start_word_guess_session() $$,
  'word_guess_daily_limit',
  'a Plus couple gets no second word the same day'
);

-- MARK: Premium is unlimited

set local request.jwt.claims = '{"sub":"eeeeeeee-5555-0000-0000-000000000005"}';

select lives_ok(
  $$ select public.start_word_guess_session() $$,
  'a Premium player starts one'
);

-- Finish it so the resume branch does not simply hand it back.
set local role postgres;
insert into public.game_responses (session_id, round_number, responder_id, answer)
select gs.id, 1, 'eeeeeeee-5555-0000-0000-000000000005', '{"value":"wordguess.v1|crane|60|1"}'
from public.game_sessions gs where gs.game_type = 'word_guess' and gs.initiator_id = 'eeeeeeee-5555-0000-0000-000000000005';

set local role authenticated;
set local request.jwt.claims = '{"sub":"eeeeeeee-5555-0000-0000-000000000005"}';

select is(
  (select (public.start_word_guess_session()).resumed),
  false,
  'and another straight after, because a finished solo board is finished'
);

select is(
  (select count(*)::int from public.game_sessions where game_type = 'word_guess' and initiator_id = 'eeeeeeee-5555-0000-0000-000000000005'),
  2,
  'Premium is not rationed'
);

-- MARK: a lapsed Premium falls back to the Plus allowance

set local request.jwt.claims = '{"sub":"dddddddd-5555-0000-0000-000000000004"}';

select lives_ok(
  $$ select public.start_word_guess_session() $$,
  'a lapsed subscriber still gets their one a day'
);

set local role postgres;
insert into public.game_responses (session_id, round_number, responder_id, answer)
select gs.id, 1, 'dddddddd-5555-0000-0000-000000000004', '{"value":"wordguess.v1|crane|60|1"}'
from public.game_sessions gs where gs.game_type = 'word_guess' and gs.initiator_id = 'dddddddd-5555-0000-0000-000000000004';

set local role authenticated;
set local request.jwt.claims = '{"sub":"dddddddd-5555-0000-0000-000000000004"}';

select throws_ok(
  $$ select public.start_word_guess_session() $$,
  'word_guess_daily_limit',
  'but not a second, however much their stale tier column says premium'
);

select * from finish();
rollback;
