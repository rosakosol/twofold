-- Connect 4: turns, gravity, and who won.
--
-- This is the first game whose state lives on the server, so it is the first one where the server
-- can be wrong about the game itself rather than about who may play it. Four things matter:
--
--   * The turn rule. Without it two moves race and the board forks — each player then holding a
--     real, self-consistent game the other is not playing, with no later point at which that can
--     be resolved.
--   * Gravity. A disc that lands in the wrong row makes every subsequent win check wrong, and it
--     would look like a rendering bug.
--   * Win detection in all four directions. Horizontal and vertical are the ones a quick test
--     catches; the diagonals are the ones that ship broken.
--   * Ending the game exactly once, and only when it is actually over.

begin;
select plan(21);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-7777-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@four.test', 'x', now(), now(), now()),
  ('bbbbbbbb-7777-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@four.test', 'x', now(), now(), now()),
  ('dddddddd-7777-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'd@four.test', 'x', now(), now(), now());

insert into public.profiles (id, first_name) values
  ('aaaaaaaa-7777-0000-0000-000000000001', 'Ada'),
  ('bbbbbbbb-7777-0000-0000-000000000002', 'Mel'),
  ('dddddddd-7777-0000-0000-000000000004', 'Dev')
on conflict (id) do update set first_name = excluded.first_name;

insert into public.couples (id, partner_a_id, partner_b_id)
values ('cccccccc-7777-0000-0000-000000000003', 'aaaaaaaa-7777-0000-0000-000000000001', 'bbbbbbbb-7777-0000-0000-000000000002');

-- MARK: starting

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-7777-0000-0000-000000000001"}';

select lives_ok(
  $$ select public.start_connect_four_session() $$,
  'a paired player can start a game'
);

select is(
  (select (public.start_connect_four_session()).resumed),
  true,
  'asking again resumes the game in progress rather than starting a second board'
);

select is(
  (select count(*)::int from public.game_sessions where game_type = 'connect_four'),
  1,
  'one board per couple at a time'
);

-- The session's id, held somewhere RLS does not reach, so the tests below can name the board even
-- as somebody who cannot see it. That is not a contrivance: "a stranger who has the id" is exactly
-- the case the ownership check exists for, and passing the id through a subquery the stranger runs
-- themselves would test RLS hiding the row instead — which it does, and which is a different
-- defence.
set local role postgres;
create temp table cf as select id from public.game_sessions where game_type = 'connect_four';
grant select on cf to authenticated;
set local role authenticated;

-- Somebody with no partner is told so, rather than being given a board nobody can answer.
set local request.jwt.claims = '{"sub":"dddddddd-7777-0000-0000-000000000004"}';

select throws_ok(
  $$ select public.start_connect_four_session() $$,
  'connect_four_needs_partner',
  'a board with one player is not a game'
);

-- MARK: turns

set local request.jwt.claims = '{"sub":"aaaaaaaa-7777-0000-0000-000000000001"}';

-- The initiator moves first.
select lives_ok(
  $$ select public.play_connect_four_move(
       (select id from cf), 0) $$,
  'the initiator moves first'
);

select throws_ok(
  $$ select public.play_connect_four_move(
       (select id from cf), 1) $$,
  'connect_four_not_your_turn',
  'and cannot move twice in a row'
);

set local request.jwt.claims = '{"sub":"dddddddd-7777-0000-0000-000000000004"}';

select throws_ok(
  $$ select public.play_connect_four_move(
       (select id from cf), 1) $$,
  'Not your game',
  'and somebody outside the couple cannot move at all'
);

set local request.jwt.claims = '{"sub":"bbbbbbbb-7777-0000-0000-000000000002"}';

select lives_ok(
  $$ select public.play_connect_four_move(
       (select id from cf), 1) $$,
  'the partner moves second'
);

select is(
  (select count(*)::int from public.game_moves
   where session_id = (select id from cf)),
  2,
  'both moves are in the log'
);

-- MARK: gravity and the board

-- `private` is not on the authenticated role's search path and is not readable by it — which is
-- the point of the schema. These assertions look directly at the helpers, so they run as the owner.
set local role postgres;

select is(
  (private.connect_four_board((select id from cf)))[5 * 7 + 0 + 1],
  1,
  'the first disc fell to the bottom row of its column'
);

select is(
  (private.connect_four_board((select id from cf)))[0 * 7 + 0 + 1],
  0,
  'and not to the top of it'
);

-- MARK: a column fills up

-- Stack column 3 to six discs, alternating, without going through the turn checks. Six is exactly
-- full; the seventh must be refused.
insert into public.game_moves (session_id, move_number, player_id, move)
select (select id from cf),
       1 + n,
       case when n % 2 = 0 then 'aaaaaaaa-7777-0000-0000-000000000001'::uuid else 'bbbbbbbb-7777-0000-0000-000000000002'::uuid end,
       '3'
from generate_series(1, 6) n;

select is(
  (select count(*)::int from unnest(private.connect_four_board(
     (select id from cf))) as cell where cell <> 0),
  8,
  'eight discs on the board, so none of the six overflowed'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-7777-0000-0000-000000000001"}';

select throws_ok(
  $$ select public.play_connect_four_move(
       (select id from cf), 3) $$,
  'connect_four_column_full',
  'a full column takes no more discs'
);

-- MARK: win detection, in every direction

set local role postgres;

-- Built as boards directly rather than as games, so each direction is one readable assertion.
-- Row 5 is the bottom.
select is(
  private.connect_four_winner(
    array_fill(0, array[42]) || '{}'::int[]
  ),
  0,
  'an empty board has no winner'
);

-- Horizontal: four in the bottom row, columns 1-4.
select is(
  private.connect_four_winner((
    select array_agg(case when i in (5*7+1+1, 5*7+2+1, 5*7+3+1, 5*7+4+1) then 1 else 0 end order by i)
    from generate_series(1, 42) i
  )),
  1,
  'four across is a win'
);

-- Vertical: column 2, rows 2-5.
select is(
  private.connect_four_winner((
    select array_agg(case when i in (2*7+2+1, 3*7+2+1, 4*7+2+1, 5*7+2+1) then 2 else 0 end order by i)
    from generate_series(1, 42) i
  )),
  2,
  'four down is a win'
);

-- Diagonal, down-right: (2,1) (3,2) (4,3) (5,4).
select is(
  private.connect_four_winner((
    select array_agg(case when i in (2*7+1+1, 3*7+2+1, 4*7+3+1, 5*7+4+1) then 1 else 0 end order by i)
    from generate_series(1, 42) i
  )),
  1,
  'four on a down-right diagonal is a win'
);

-- Diagonal, down-left: (2,5) (3,4) (4,3) (5,2).
select is(
  private.connect_four_winner((
    select array_agg(case when i in (2*7+5+1, 3*7+4+1, 4*7+3+1, 5*7+2+1) then 2 else 0 end order by i)
    from generate_series(1, 42) i
  )),
  2,
  'four on a down-left diagonal is a win'
);

-- Three in a row is not four, and a run broken by the other colour is not a run. Both are the
-- off-by-one this function is most likely to get wrong.
select is(
  private.connect_four_winner((
    select array_agg(case when i in (5*7+1+1, 5*7+2+1, 5*7+3+1) then 1 else 0 end order by i)
    from generate_series(1, 42) i
  )),
  0,
  'three across is not a win'
);

select is(
  private.connect_four_winner((
    select array_agg(
      case when i in (5*7+1+1, 5*7+2+1, 5*7+4+1, 5*7+5+1) then 1
           when i = 5*7+3+1 then 2
           else 0 end order by i)
    from generate_series(1, 42) i
  )),
  0,
  'a run split by the other player is not a win'
);

-- A line that wraps from the end of one row to the start of the next is the classic array-indexing
-- bug, and it looks exactly like a win nobody made.
select is(
  private.connect_four_winner((
    select array_agg(case when i in (2*7+5+1, 2*7+6+1, 3*7+0+1, 3*7+1+1) then 1 else 0 end order by i)
    from generate_series(1, 42) i
  )),
  0,
  'a run that wraps around the edge of the board is not a win'
);

select * from finish();
rollback;
