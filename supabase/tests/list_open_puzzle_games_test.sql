-- What the hub shows as "on right now", and whose move it says it is.
--
-- Getting the turn wrong here is worse than showing nothing: a card that says "your turn" and then
-- opens a board the server will not accept a move on teaches people not to trust the hub. So the
-- rule has to be derived exactly the way `play_connect_four_move` and `play-chess-move` derive it.
--
-- The other failure is quieter: a finished game still listed. One board per couple means a
-- completed chess game left in the list would look like the game they are playing.

begin;
select plan(12);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-1010-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@open.test', 'x', now(), now(), now()),
  ('bbbbbbbb-1010-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@open.test', 'x', now(), now(), now());

insert into public.profiles (id, first_name) values
  ('aaaaaaaa-1010-0000-0000-000000000001', 'Ada'),
  ('bbbbbbbb-1010-0000-0000-000000000002', 'Mel')
on conflict (id) do update set first_name = excluded.first_name;

insert into public.couples (id, partner_a_id, partner_b_id)
values ('cccccccc-1010-0000-0000-000000000003', 'aaaaaaaa-1010-0000-0000-000000000001', 'bbbbbbbb-1010-0000-0000-000000000002');

-- A Connect 4 board started by Ada, with no moves on it: Ada moves first.
insert into public.game_sessions (id, couple_id, game_type, initiator_id, status, total_rounds, is_daily)
values ('11111111-1010-0000-0000-000000000011', 'cccccccc-1010-0000-0000-000000000003', 'connect_four', 'aaaaaaaa-1010-0000-0000-000000000001', 'active', 1, false);
insert into public.game_session_rounds (session_id, round_number, content_id)
values ('11111111-1010-0000-0000-000000000011', 1, gen_random_uuid());

-- A Hard sudoku neither has finished.
insert into public.game_sessions (id, couple_id, game_type, initiator_id, status, total_rounds, is_daily)
values ('22222222-1010-0000-0000-000000000022', 'cccccccc-1010-0000-0000-000000000003', 'sudoku', 'aaaaaaaa-1010-0000-0000-000000000001', 'active', 1, false);
insert into public.game_session_rounds (session_id, round_number, content_id, difficulty)
values ('22222222-1010-0000-0000-000000000022', 1, gen_random_uuid(), 'hard');

-- A finished chess game, which must not appear at all.
insert into public.game_sessions (id, couple_id, game_type, initiator_id, status, total_rounds, is_daily)
values ('33333333-1010-0000-0000-000000000033', 'cccccccc-1010-0000-0000-000000000003', 'chess', 'aaaaaaaa-1010-0000-0000-000000000001', 'completed', 1, false);
insert into public.game_session_rounds (session_id, round_number, content_id)
values ('33333333-1010-0000-0000-000000000033', 1, gen_random_uuid());

-- A deck game, which has its own place on the hub and must not be duplicated here.
insert into public.game_sessions (id, couple_id, game_type, initiator_id, status, total_rounds, is_daily)
values ('44444444-1010-0000-0000-000000000044', 'cccccccc-1010-0000-0000-000000000003', 'this_or_that', 'aaaaaaaa-1010-0000-0000-000000000001', 'active', 5, false);

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-1010-0000-0000-000000000001"}';

select is(
  (select count(*)::int from public.list_open_puzzle_games()),
  2,
  'two games are open — the finished chess game and the deck game are not listed'
);

select is(
  (select count(*)::int from public.list_open_puzzle_games() where game_type = 'this_or_that'),
  0,
  'deck games keep to their own section rather than being counted twice on one screen'
);

select is(
  (select count(*)::int from public.list_open_puzzle_games() where game_type = 'chess'),
  0,
  'a completed board is not something you are still playing'
);

select is(
  (select label from public.list_open_puzzle_games() where game_type = 'sudoku'),
  'hard',
  'the sudoku says which one it is'
);

-- MARK: whose move it is, on a board

select is(
  (select is_my_turn from public.list_open_puzzle_games() where game_type = 'connect_four'),
  true,
  'an empty board is the initiator''s move'
);

set local request.jwt.claims = '{"sub":"bbbbbbbb-1010-0000-0000-000000000002"}';

select is(
  (select is_my_turn from public.list_open_puzzle_games() where game_type = 'connect_four'),
  false,
  'and not the partner''s'
);

-- One disc, and it swaps.
set local role postgres;
insert into public.game_moves (session_id, move_number, player_id, move)
values ('11111111-1010-0000-0000-000000000011', 0, 'aaaaaaaa-1010-0000-0000-000000000001', '3');

set local role authenticated;

select is(
  (select is_my_turn from public.list_open_puzzle_games() where game_type = 'connect_four'),
  true,
  'after one move it is the partner''s'
);

set local request.jwt.claims = '{"sub":"aaaaaaaa-1010-0000-0000-000000000001"}';

select is(
  (select is_my_turn from public.list_open_puzzle_games() where game_type = 'connect_four'),
  false,
  'and no longer the initiator''s — the same parity the move RPC enforces'
);

-- MARK: "your turn" on a puzzle means "you have not finished it"

select is(
  (select is_my_turn from public.list_open_puzzle_games() where game_type = 'sudoku'),
  true,
  'an unfinished puzzle is yours to play'
);

set local role postgres;
insert into public.game_responses (session_id, round_number, responder_id, answer)
values ('22222222-1010-0000-0000-000000000022', 1, 'aaaaaaaa-1010-0000-0000-000000000001',
        '{"value":"sudoku.v1|x|0|1"}');

set local role authenticated;

select is(
  (select is_my_turn from public.list_open_puzzle_games() where game_type = 'sudoku'),
  false,
  'once you have finished it, it is not your turn any more'
);

select is(
  (select count(*)::int from public.list_open_puzzle_games() where game_type = 'sudoku'),
  1,
  'but it stays listed — the partner has not finished, and the comparison is what they are waiting for'
);

-- MARK: ordering puts what needs you first, ahead of what was touched most recently

-- A word search Ada has never opened, deliberately stale. The sudoku above was touched a moment
-- ago (finishing it updated the session), so ordering by recency alone would put the sudoku —
-- which needs nothing from her — above the game that does.
set local role postgres;
insert into public.game_sessions (id, couple_id, game_type, initiator_id, status, total_rounds, is_daily, updated_at)
values ('55555555-1010-0000-0000-000000000055', 'cccccccc-1010-0000-0000-000000000003', 'word_search', 'bbbbbbbb-1010-0000-0000-000000000002', 'active', 1, false, now() - interval '9 days');
insert into public.game_session_rounds (session_id, round_number, content_id, theme)
values ('55555555-1010-0000-0000-000000000055', 1, gen_random_uuid(), 'travel');

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-1010-0000-0000-000000000001"}';

select is(
  (select game_type from public.list_open_puzzle_games() limit 1),
  'word_search',
  'a nine-day-old game that needs you outranks a fresh one that does not'
);

select * from finish();
rollback;
