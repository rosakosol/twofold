-- Abandoning a game session, and who is allowed to.
--
-- This matters for sudoku in a way it never did for the other games. `start_sudoku_session` resumes
-- by couple and difficulty, so an unfinished Hard is handed straight back on the next tap, and
-- abandoning is the only way out of it. A solo session's `couple_id` is null and
-- `is_couple_member(null)` is false, so the original guard matched no rows, updated nothing, and —
-- returning void — reported success. A solo player was stuck with a puzzle they could neither
-- finish nor escape, and the app had no way to know.
--
-- So the cases worth pinning are: a solo session is abandonable by its owner, a couple's session by
-- either partner, and neither by anybody else — with a failure that is loud, because the whole bug
-- was that doing nothing and succeeding looked identical.

begin;
select plan(8);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-3333-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@abandon.test', 'x', now(), now(), now()),
  ('bbbbbbbb-3333-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@abandon.test', 'x', now(), now(), now()),
  ('dddddddd-3333-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'd@abandon.test', 'x', now(), now(), now());

insert into public.profiles (id, first_name) values
  ('aaaaaaaa-3333-0000-0000-000000000001', 'Ada'),
  ('bbbbbbbb-3333-0000-0000-000000000002', 'Mel'),
  ('dddddddd-3333-0000-0000-000000000004', 'Dev')
on conflict (id) do update set first_name = excluded.first_name;

insert into public.couples (id, partner_a_id, partner_b_id)
values ('cccccccc-3333-0000-0000-000000000003', 'aaaaaaaa-3333-0000-0000-000000000001', 'bbbbbbbb-3333-0000-0000-000000000002');

-- A solo sudoku, exactly as start_sudoku_session writes one: no couple, initiator is the player.
insert into public.game_sessions (id, couple_id, game_type, initiator_id, status, total_rounds, is_daily)
values ('11111111-3333-0000-0000-000000000011', null, 'sudoku', 'aaaaaaaa-3333-0000-0000-000000000001', 'active', 1, false);

-- And a couple's one.
insert into public.game_sessions (id, couple_id, game_type, initiator_id, status, total_rounds, is_daily)
values ('22222222-3333-0000-0000-000000000022', 'cccccccc-3333-0000-0000-000000000003', 'sudoku', 'aaaaaaaa-3333-0000-0000-000000000001', 'active', 1, false);

-- MARK: a solo session belongs to whoever started it

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-3333-0000-0000-000000000001"}';

select lives_ok(
  $$ select public.abandon_game_session('11111111-3333-0000-0000-000000000011') $$,
  'the owner of a solo session can abandon it'
);

reset role;
select is(
  (select status from public.game_sessions where id = '11111111-3333-0000-0000-000000000011'),
  'abandoned',
  'and the row actually changed — the original bug was a silent no-op here'
);

-- MARK: a couple's session, from both sides

set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-3333-0000-0000-000000000002"}';

select lives_ok(
  $$ select public.abandon_game_session('22222222-3333-0000-0000-000000000022') $$,
  'the partner who did not start it can still abandon it'
);

reset role;
select is(
  (select status from public.game_sessions where id = '22222222-3333-0000-0000-000000000022'),
  'abandoned',
  'one shared grid, either of them may put it down'
);

-- MARK: and nobody else

insert into public.game_sessions (id, couple_id, game_type, initiator_id, status, total_rounds, is_daily)
values ('33333333-3333-0000-0000-000000000033', null, 'sudoku', 'aaaaaaaa-3333-0000-0000-000000000001', 'active', 1, false);

set local role authenticated;
set local request.jwt.claims = '{"sub":"dddddddd-3333-0000-0000-000000000004"}';

select throws_ok(
  $$ select public.abandon_game_session('33333333-3333-0000-0000-000000000033') $$,
  '42501',
  'No such game session',
  'a stranger cannot abandon somebody else''s solo puzzle'
);

select throws_ok(
  $$ select public.abandon_game_session('99999999-3333-0000-0000-000000000099') $$,
  '42501',
  'No such game session',
  'and a session that does not exist raises rather than quietly succeeding'
);

reset role;
select is(
  (select status from public.game_sessions where id = '33333333-3333-0000-0000-000000000033'),
  'active',
  'the stranger changed nothing'
);

-- The negative control for the raise: a real abandon still succeeds after all that, so the
-- exception above is about permission rather than the function having stopped working.
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-3333-0000-0000-000000000001"}';
select lives_ok(
  $$ select public.abandon_game_session('33333333-3333-0000-0000-000000000033') $$,
  'the real owner can still abandon it afterwards'
);

select * from finish();
rollback;
