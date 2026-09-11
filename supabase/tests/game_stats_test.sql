-- The running record: who is ahead, and at what.
--
-- Three ways this goes wrong quietly, and all three would show as a plausible-looking number:
--
--   * Counting a game only one of them played. A word somebody solved while their partner never
--     opened it is not a win over anybody, and counting it lets one of them lead a record the other
--     has not played.
--   * Scoring an unsolved board. A Word Guess that ran out of guesses has no score — treating it
--     as six would make a miss beat a win in seven.
--   * Getting the direction wrong. Fewer guesses and less time are both better, and a record that
--     silently ranked them the other way would look exactly as convincing.

begin;
select plan(14);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-1111-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@stats.test', 'x', now(), now(), now()),
  ('bbbbbbbb-1111-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@stats.test', 'x', now(), now(), now());

insert into public.profiles (id, first_name) values
  ('aaaaaaaa-1111-0000-0000-000000000001', 'Ada'),
  ('bbbbbbbb-1111-0000-0000-000000000002', 'Mel')
on conflict (id) do update set first_name = excluded.first_name;

insert into public.couples (id, partner_a_id, partner_b_id)
values ('cccccccc-1111-0000-0000-000000000003', 'aaaaaaaa-1111-0000-0000-000000000001', 'bbbbbbbb-1111-0000-0000-000000000002');

-- MARK: Word Guess — three boards

-- Ada 3 guesses, Mel 5: Ada wins.
insert into public.game_sessions (id, couple_id, game_type, initiator_id, status, total_rounds, is_daily)
values ('11111111-1111-0000-0000-000000000011', 'cccccccc-1111-0000-0000-000000000003', 'word_guess', 'aaaaaaaa-1111-0000-0000-000000000001', 'completed', 1, false);
insert into public.game_responses (session_id, round_number, responder_id, answer) values
  ('11111111-1111-0000-0000-000000000011', 1, 'aaaaaaaa-1111-0000-0000-000000000001', '{"value":"wordguess.v1|crane,toads,roast|60|1"}'),
  ('11111111-1111-0000-0000-000000000011', 1, 'bbbbbbbb-1111-0000-0000-000000000002', '{"value":"wordguess.v1|crane,solid,tonal,brisk,roast|90|1"}');

-- Ada missed in six, Mel got it in six: Mel wins, because a miss has no score at all.
insert into public.game_sessions (id, couple_id, game_type, initiator_id, status, total_rounds, is_daily)
values ('22222222-1111-0000-0000-000000000022', 'cccccccc-1111-0000-0000-000000000003', 'word_guess', 'aaaaaaaa-1111-0000-0000-000000000001', 'completed', 1, false);
insert into public.game_responses (session_id, round_number, responder_id, answer) values
  ('22222222-1111-0000-0000-000000000022', 1, 'aaaaaaaa-1111-0000-0000-000000000001', '{"value":"wordguess.v1|crane,solid,tonal,brisk,fudge,tempo|200|0"}'),
  ('22222222-1111-0000-0000-000000000022', 1, 'bbbbbbbb-1111-0000-0000-000000000002', '{"value":"wordguess.v1|crane,solid,tonal,brisk,fudge,roast|150|1"}');

-- Only Ada played this one. It must count towards nobody's record.
insert into public.game_sessions (id, couple_id, game_type, initiator_id, status, total_rounds, is_daily)
values ('33333333-1111-0000-0000-000000000033', 'cccccccc-1111-0000-0000-000000000003', 'word_guess', 'aaaaaaaa-1111-0000-0000-000000000001', 'waiting_for_partner', 1, false);
insert into public.game_responses (session_id, round_number, responder_id, answer) values
  ('33333333-1111-0000-0000-000000000033', 1, 'aaaaaaaa-1111-0000-0000-000000000001', '{"value":"wordguess.v1|crane,roast|40|1"}');

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-1111-0000-0000-000000000001"}';

select is(
  (select my_wins from public.get_game_stats() where game_type = 'word_guess'),
  1,
  'one word guess won'
);

select is(
  (select partner_wins from public.get_game_stats() where game_type = 'word_guess'),
  1,
  'and one lost — the six-guess miss does not beat a six-guess win'
);

select is(
  (select draws from public.get_game_stats() where game_type = 'word_guess'),
  0,
  'no dead heats'
);

select is(
  (select my_wins + partner_wins + draws from public.get_game_stats() where game_type = 'word_guess'),
  2,
  'the board only one of them played counts towards nobody'
);

select is(
  (select my_finished from public.get_game_stats() where game_type = 'word_guess'),
  2,
  'Ada solved two of the three she played'
);

select is(
  (select my_best from public.get_game_stats() where game_type = 'word_guess'),
  2::numeric,
  'her best is the two-guess board, even though it counts towards no head-to-head'
);

select is(
  (select partner_best from public.get_game_stats() where game_type = 'word_guess'),
  5::numeric,
  'and lower is better — five, not six'
);

-- MARK: Word Search — scored on time, and kept per theme

set local role postgres;
insert into public.game_sessions (id, couple_id, game_type, initiator_id, status, total_rounds, is_daily)
values ('44444444-1111-0000-0000-000000000044', 'cccccccc-1111-0000-0000-000000000003', 'word_search', 'aaaaaaaa-1111-0000-0000-000000000001', 'completed', 1, false);
insert into public.game_session_rounds (session_id, round_number, content_id, theme)
values ('44444444-1111-0000-0000-000000000044', 1, gen_random_uuid(), 'travel');
insert into public.game_responses (session_id, round_number, responder_id, answer) values
  ('44444444-1111-0000-0000-000000000044', 1, 'aaaaaaaa-1111-0000-0000-000000000001', '{"value":"wordsearch.v1|FLIGHT,GATE|233|1"}'),
  ('44444444-1111-0000-0000-000000000044', 1, 'bbbbbbbb-1111-0000-0000-000000000002', '{"value":"wordsearch.v1|FLIGHT,GATE|154|1"}');

set local role authenticated;

select is(
  (select variant from public.get_game_stats() where game_type = 'word_search'),
  'travel',
  'a word search record is kept per theme'
);

select is(
  (select partner_wins from public.get_game_stats() where game_type = 'word_search'),
  1,
  'the quicker clear wins'
);

select is(
  (select my_best from public.get_game_stats() where game_type = 'word_search'),
  233::numeric,
  'and the best is a time'
);

-- MARK: the boards — read from the outcome the game recorded

set local role postgres;
insert into public.game_sessions (id, couple_id, game_type, initiator_id, status, total_rounds, is_daily, winner_id, outcome, completed_at)
values
  ('55555555-1111-0000-0000-000000000055', 'cccccccc-1111-0000-0000-000000000003', 'connect_four', 'aaaaaaaa-1111-0000-0000-000000000001', 'completed', 1, false, 'aaaaaaaa-1111-0000-0000-000000000001', 'win', now()),
  ('66666666-1111-0000-0000-000000000066', 'cccccccc-1111-0000-0000-000000000003', 'connect_four', 'aaaaaaaa-1111-0000-0000-000000000001', 'completed', 1, false, null, 'draw', now()),
  ('77777777-1111-0000-0000-000000000077', 'cccccccc-1111-0000-0000-000000000003', 'chess', 'aaaaaaaa-1111-0000-0000-000000000001', 'completed', 1, false, 'bbbbbbbb-1111-0000-0000-000000000002', 'win', now()),
  -- Ended without being played out: no outcome, so it belongs in nobody's record.
  ('88888888-1111-0000-0000-000000000088', 'cccccccc-1111-0000-0000-000000000003', 'chess', 'aaaaaaaa-1111-0000-0000-000000000001', 'abandoned', 1, false, null, null, now());

set local role authenticated;

select is(
  (select my_wins from public.get_game_stats() where game_type = 'connect_four'),
  1,
  'a Connect 4 win is counted'
);

select is(
  (select draws from public.get_game_stats() where game_type = 'connect_four'),
  1,
  'and so is a full board with no line'
);

select is(
  (select partner_wins from public.get_game_stats() where game_type = 'chess'),
  1,
  'a chess result is read from what the edge function recorded, since it cannot be recomputed here'
);

select is(
  (select my_wins + partner_wins + draws from public.get_game_stats() where game_type = 'chess'),
  1,
  'a game ended without being played out is in nobody''s record'
);

select * from finish();
rollback;
