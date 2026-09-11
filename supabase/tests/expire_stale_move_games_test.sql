-- Closing Connect 4 boards nobody came back to.
--
-- The cases that matter are the two ways this can be wrong, and they are opposites:
--
--   * Expiring too eagerly. This game has no clock and is meant to be played a move at a time; a
--     rule that closes a slow game closes a game two people are still playing, and the move log is
--     append-only so there is no reopening it.
--   * Not expiring at all. `start_connect_four_session` allows one board per couple, so a game
--     forgotten in March is a game they cannot start in April — and nothing on the screen would
--     explain why there is no new one.

begin;
select plan(9);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-8888-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@expire.test', 'x', now(), now(), now()),
  ('bbbbbbbb-8888-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@expire.test', 'x', now(), now(), now());

insert into public.profiles (id, first_name) values
  ('aaaaaaaa-8888-0000-0000-000000000001', 'Ada'),
  ('bbbbbbbb-8888-0000-0000-000000000002', 'Mel')
on conflict (id) do update set first_name = excluded.first_name;

insert into public.couples (id, partner_a_id, partner_b_id)
values ('cccccccc-8888-0000-0000-000000000003', 'aaaaaaaa-8888-0000-0000-000000000001', 'bbbbbbbb-8888-0000-0000-000000000002');

-- Three boards: one long dead, one quiet but recent, one old with a recent move on it.
insert into public.game_sessions (id, couple_id, game_type, initiator_id, status, total_rounds, is_daily, created_at)
values
  ('11111111-8888-0000-0000-000000000011', 'cccccccc-8888-0000-0000-000000000003', 'connect_four', 'aaaaaaaa-8888-0000-0000-000000000001', 'active', 1, false, now() - interval '30 days'),
  ('22222222-8888-0000-0000-000000000022', 'cccccccc-8888-0000-0000-000000000003', 'connect_four', 'aaaaaaaa-8888-0000-0000-000000000001', 'active', 1, false, now() - interval '2 days'),
  ('33333333-8888-0000-0000-000000000033', 'cccccccc-8888-0000-0000-000000000003', 'connect_four', 'aaaaaaaa-8888-0000-0000-000000000001', 'active', 1, false, now() - interval '60 days');

-- The 60-day-old board has a move from yesterday: a long game, still being played.
insert into public.game_moves (session_id, move_number, player_id, move, created_at)
values ('33333333-8888-0000-0000-000000000033', 0, 'aaaaaaaa-8888-0000-0000-000000000001', '3', now() - interval '1 day');

-- The 30-day-old one was played a little, a month ago, and then dropped.
insert into public.game_moves (session_id, move_number, player_id, move, created_at)
values ('11111111-8888-0000-0000-000000000011', 0, 'aaaaaaaa-8888-0000-0000-000000000001', '0', now() - interval '29 days');

select is(
  private.expire_stale_move_games(),
  1,
  'exactly one board expired'
);

select is(
  (select status::text from public.game_sessions where id = '11111111-8888-0000-0000-000000000011'),
  'archived',
  'the board last touched a month ago is closed'
);

select is(
  (select status::text from public.game_sessions where id = '22222222-8888-0000-0000-000000000022'),
  'active',
  'a board started two days ago is left alone, even with no moves on it'
);

-- The one that would be easiest to get wrong: old board, recent move.
select is(
  (select status::text from public.game_sessions where id = '33333333-8888-0000-0000-000000000033'),
  'active',
  'a two-month-old game with a move yesterday is still being played'
);

select is(
  (select status::text from public.game_sessions where id = '11111111-8888-0000-0000-000000000011'),
  'archived',
  'and it is archived rather than abandoned — the system closed it, nobody put it down'
);

-- Idempotent: the nightly run must not keep counting the same board.
select is(
  private.expire_stale_move_games(),
  0,
  'running it again closes nothing, having already closed it'
);

-- MARK: it never reaches past Connect 4

insert into public.game_sessions (id, couple_id, game_type, initiator_id, status, total_rounds, is_daily, created_at)
values ('44444444-8888-0000-0000-000000000044', 'cccccccc-8888-0000-0000-000000000003', 'sudoku', 'aaaaaaaa-8888-0000-0000-000000000001', 'active', 1, false, now() - interval '90 days');

select is(
  private.expire_stale_move_games(),
  0,
  'a 90-day-old sudoku is not a stale board'
);

select is(
  (select status::text from public.game_sessions where id = '44444444-8888-0000-0000-000000000044'),
  'active',
  'a half-finished puzzle is nobody''s turn, so it waits as long as it likes'
);

-- MARK: starting a game closes this couple's stale board itself

-- Back to one dead board, so the RPC has something to clear.
update public.game_sessions set status = 'active' where id = '11111111-8888-0000-0000-000000000011';
delete from public.game_sessions where id in ('22222222-8888-0000-0000-000000000022', '33333333-8888-0000-0000-000000000033');

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-8888-0000-0000-000000000001"}';

select is(
  (select (public.start_connect_four_session()).resumed),
  false,
  'starting a game clears the couple''s dead board rather than resuming it'
);

select * from finish();
rollback;
