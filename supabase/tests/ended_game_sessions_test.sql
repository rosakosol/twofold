-- A game that has ended stays ended (2-games-NEW-1, and the abandon status check).
--
-- `advance_game_session` used to rewrite the status on every new response without looking at what
-- it was, and the insert policy on `game_responses` let an answer into a session in any status. So
-- the first late answer to an `abandoned` or `archived` session put it back to `active` (a couple's)
-- or `completed` (a solo one). The way that happens in the app: one partner abandons a shared
-- puzzle while the other finishes it offline, and the finisher's result, sent on reconnect, brings
-- the puzzle back for both of them.
--
-- And `abandon_game_session` had no status check at all, so any client could turn a finished
-- result into an abandonment.

begin;
select plan(17);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-4444-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@ended.test', 'x', now(), now(), now()),
  ('bbbbbbbb-4444-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@ended.test', 'x', now(), now(), now()),
  ('dddddddd-4444-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'd@ended.test', 'x', now(), now(), now());

insert into public.profiles (id, first_name, subscription_active, subscription_tier) values
  ('aaaaaaaa-4444-0000-0000-000000000001', 'Ada', true, 'premium'),
  ('bbbbbbbb-4444-0000-0000-000000000002', 'Mel', true, 'premium'),
  ('dddddddd-4444-0000-0000-000000000004', 'Dev', true, 'premium')
on conflict (id) do update
  set first_name = excluded.first_name,
      subscription_active = excluded.subscription_active,
      subscription_tier = excluded.subscription_tier;

insert into public.couples (id, partner_a_id, partner_b_id)
values ('cccccccc-4444-0000-0000-000000000003', 'aaaaaaaa-4444-0000-0000-000000000001', 'bbbbbbbb-4444-0000-0000-000000000002');

-- A shared sudoku Ada abandoned while Mel was still solving it.
insert into public.game_sessions (id, couple_id, game_type, initiator_id, status, total_rounds, is_daily)
values ('11111111-4444-0000-0000-000000000011', 'cccccccc-4444-0000-0000-000000000003', 'sudoku', 'aaaaaaaa-4444-0000-0000-000000000001', 'abandoned', 1, false);

-- A shared word search the cron archived.
insert into public.game_sessions (id, couple_id, game_type, initiator_id, status, total_rounds, is_daily)
values ('22222222-4444-0000-0000-000000000022', 'cccccccc-4444-0000-0000-000000000003', 'word_search', 'aaaaaaaa-4444-0000-0000-000000000001', 'archived', 1, false);

-- Dev's own solo sudoku, abandoned.
insert into public.game_sessions (id, couple_id, game_type, initiator_id, status, total_rounds, is_daily)
values ('33333333-4444-0000-0000-000000000033', null, 'sudoku', 'dddddddd-4444-0000-0000-000000000004', 'abandoned', 1, false);

-- A live one, as the control for all of the above.
insert into public.game_sessions (id, couple_id, game_type, initiator_id, status, total_rounds, is_daily)
values ('44444444-4444-0000-0000-000000000044', 'cccccccc-4444-0000-0000-000000000003', 'sudoku', 'aaaaaaaa-4444-0000-0000-000000000001', 'active', 1, false);

-- A solo solve that has completed.
insert into public.game_sessions (id, couple_id, game_type, initiator_id, status, total_rounds, is_daily, completed_at)
values ('55555555-4444-0000-0000-000000000055', null, 'sudoku', 'dddddddd-4444-0000-0000-000000000004', 'completed', 1, false, now());
insert into public.game_responses (session_id, round_number, responder_id, answer, is_correct)
values ('55555555-4444-0000-0000-000000000055', 1, 'dddddddd-4444-0000-0000-000000000004', '{"value":"solved"}', true);

-- An answer Mel gave before Ada abandoned a second shared puzzle, to try the upsert's update path.
insert into public.game_sessions (id, couple_id, game_type, initiator_id, status, total_rounds, is_daily)
values ('66666666-4444-0000-0000-000000000066', 'cccccccc-4444-0000-0000-000000000003', 'word_guess', 'aaaaaaaa-4444-0000-0000-000000000001', 'active', 1, false);
insert into public.game_responses (session_id, round_number, responder_id, answer, is_correct)
values ('66666666-4444-0000-0000-000000000066', 1, 'bbbbbbbb-4444-0000-0000-000000000002', '{"value":"first"}', false);
update public.game_sessions set status = 'abandoned' where id = '66666666-4444-0000-0000-000000000066';

-- MARK: a late answer to an ended session is refused

set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-4444-0000-0000-000000000002"}';

select throws_ok(
  $$ insert into public.game_responses (session_id, round_number, responder_id, answer, is_correct)
     values ('11111111-4444-0000-0000-000000000011', 1, 'bbbbbbbb-4444-0000-0000-000000000002', '{"value":"late"}', true) $$,
  '42501',
  null,
  'a result sent after the partner abandoned the puzzle is refused'
);

select throws_ok(
  $$ insert into public.game_responses (session_id, round_number, responder_id, answer, is_correct)
     values ('22222222-4444-0000-0000-000000000022', 1, 'bbbbbbbb-4444-0000-0000-000000000002', '{"value":"late"}', true) $$,
  '42501',
  null,
  'and so is one sent after the cron archived it'
);

-- The way the app actually sends it: an upsert, which takes the update path once a row exists.
select throws_ok(
  $$ insert into public.game_responses (session_id, round_number, responder_id, answer, is_correct)
     values ('66666666-4444-0000-0000-000000000066', 1, 'bbbbbbbb-4444-0000-0000-000000000002', '{"value":"second"}', true)
     on conflict (session_id, round_number, responder_id) do update set answer = excluded.answer, is_correct = excluded.is_correct $$,
  '42501',
  null,
  'an upsert over an answer already in an abandoned session is refused too'
);

select lives_ok(
  $$ insert into public.game_responses (session_id, round_number, responder_id, answer, is_correct)
     values ('44444444-4444-0000-0000-000000000044', 1, 'bbbbbbbb-4444-0000-0000-000000000002', '{"value":"live"}', true) $$,
  'an answer to a live session still goes in'
);

set local request.jwt.claims = '{"sub":"dddddddd-4444-0000-0000-000000000004"}';

select throws_ok(
  $$ insert into public.game_responses (session_id, round_number, responder_id, answer, is_correct)
     values ('33333333-4444-0000-0000-000000000033', 1, 'dddddddd-4444-0000-0000-000000000004', '{"value":"late"}', true) $$,
  '42501',
  null,
  'a solo player''s result to a puzzle they abandoned is refused'
);

-- A result resent after it already landed, which is what the retry after a lost reply does.
select lives_ok(
  $$ insert into public.game_responses (session_id, round_number, responder_id, answer, is_correct)
     values ('55555555-4444-0000-0000-000000000055', 1, 'dddddddd-4444-0000-0000-000000000004', '{"value":"solved"}', true)
     on conflict (session_id, round_number, responder_id) do update set answer = excluded.answer, is_correct = excluded.is_correct $$,
  'resending a result to a completed session still works, so a retry is harmless'
);

reset role;

select is(
  (select status::text from public.game_sessions where id = '11111111-4444-0000-0000-000000000011'),
  'abandoned',
  'the abandoned puzzle stayed abandoned'
);

select is(
  (select status::text from public.game_sessions where id = '22222222-4444-0000-0000-000000000022'),
  'archived',
  'the archived one stayed archived'
);

select is(
  (select status::text from public.game_sessions where id = '55555555-4444-0000-0000-000000000055'),
  'completed',
  'and the resent result left the completed one completed'
);

-- MARK: and the trigger does not revive one either

-- Past RLS, as a security definer function or the service role would be. The policy is the front
-- door; this is the trigger not reopening the session whoever gets an answer in.
insert into public.game_responses (session_id, round_number, responder_id, answer, is_correct)
values ('33333333-4444-0000-0000-000000000033', 1, 'dddddddd-4444-0000-0000-000000000004', '{"value":"late"}', true);

select is(
  (select status::text from public.game_sessions where id = '33333333-4444-0000-0000-000000000033'),
  'abandoned',
  'an answer that gets past RLS does not complete an abandoned solo session'
);

insert into public.game_responses (session_id, round_number, responder_id, answer, is_correct)
values ('22222222-4444-0000-0000-000000000022', 1, 'aaaaaaaa-4444-0000-0000-000000000001', '{"value":"late"}', true);

select is(
  (select status::text from public.game_sessions where id = '22222222-4444-0000-0000-000000000022'),
  'archived',
  'nor reactivate an archived couple session'
);

-- MARK: abandoning only ends a game that is still being played

set local role authenticated;
set local request.jwt.claims = '{"sub":"dddddddd-4444-0000-0000-000000000004"}';

select lives_ok(
  $$ select public.abandon_game_session('55555555-4444-0000-0000-000000000055') $$,
  'abandoning a finished solve does not raise — it is over either way'
);

reset role;
select is(
  (select status::text from public.game_sessions where id = '55555555-4444-0000-0000-000000000055'),
  'completed',
  'but it stays completed, so the result is kept'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-4444-0000-0000-000000000002"}';

select lives_ok(
  $$ select public.abandon_game_session('22222222-4444-0000-0000-000000000022') $$,
  'abandoning a session the partner or the cron already ended is quietly a no-op'
);

reset role;
select is(
  (select status::text from public.game_sessions where id = '22222222-4444-0000-0000-000000000022'),
  'archived',
  'and an archived session stays archived'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-4444-0000-0000-000000000002"}';

select lives_ok(
  $$ select public.abandon_game_session('44444444-4444-0000-0000-000000000044') $$,
  'a live session can still be abandoned'
);

reset role;
select is(
  (select status::text from public.game_sessions where id = '44444444-4444-0000-0000-000000000044'),
  'abandoned',
  'and it is'
);

select * from finish();
rollback;
