-- Starting a chess game: who may, and what happens to a board nobody finishes.
--
-- Chess is the only one of the five whose tiering is a game-level flag rather than a property of
-- its content — there is no deck to gate and no difficulty to sell — so the Premium check is the
-- whole of its gating and the only place it can be got wrong.
--
-- Moves are deliberately not tested here, because they do not happen here: `game_moves` grants no
-- insert to `authenticated` at all, and every move goes through the `play-chess-move` edge
-- function, which replays the log with chess.js. What the rules do is tested in
-- `_shared/chess-rules.test.ts`; what the database does is this.

begin;
select plan(11);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-9999-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@chess.test', 'x', now(), now(), now()),
  ('bbbbbbbb-9999-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@chess.test', 'x', now(), now(), now()),
  ('dddddddd-9999-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'd@chess.test', 'x', now(), now(), now()),
  ('eeeeeeee-9999-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'e@chess.test', 'x', now(), now(), now());

insert into public.profiles (id, first_name, subscription_active, subscription_tier) values
  ('aaaaaaaa-9999-0000-0000-000000000001', 'Ada', true, 'premium'),
  -- The partner bought nothing. One subscription covers the couple, so they must still get in.
  ('bbbbbbbb-9999-0000-0000-000000000002', 'Mel', false, null),
  ('dddddddd-9999-0000-0000-000000000004', 'Dev', true, 'plus'),
  ('eeeeeeee-9999-0000-0000-000000000005', 'Eve', true, 'plus')
on conflict (id) do update
  set first_name = excluded.first_name,
      subscription_active = excluded.subscription_active,
      subscription_tier = excluded.subscription_tier;

insert into public.couples (id, partner_a_id, partner_b_id) values
  ('cccccccc-9999-0000-0000-000000000003', 'aaaaaaaa-9999-0000-0000-000000000001', 'bbbbbbbb-9999-0000-0000-000000000002'),
  ('cccccccc-9999-0000-0000-000000000013', 'dddddddd-9999-0000-0000-000000000004', 'eeeeeeee-9999-0000-0000-000000000005');

-- MARK: Premium, per couple

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-9999-0000-0000-000000000001"}';

select lives_ok(
  $$ select public.start_chess_session() $$,
  'a Premium subscriber can start a game'
);

set local request.jwt.claims = '{"sub":"bbbbbbbb-9999-0000-0000-000000000002"}';

select is(
  (select (public.start_chess_session()).resumed),
  true,
  'and their partner, who bought nothing, joins the same board'
);

select is(
  (select count(*)::int from public.game_sessions where game_type = 'chess' and couple_id = 'cccccccc-9999-0000-0000-000000000003'),
  1,
  'one board per couple — the partner joined rather than starting a second'
);

set local request.jwt.claims = '{"sub":"dddddddd-9999-0000-0000-000000000004"}';

select throws_ok(
  $$ select public.start_chess_session() $$,
  'chess_requires_premium',
  'a Plus couple is refused'
);

select is(
  (select count(*)::int from public.game_sessions where game_type = 'chess' and couple_id = 'cccccccc-9999-0000-0000-000000000013'),
  0,
  'and no board was created on the way to refusing them'
);

-- MARK: it takes two

set local role postgres;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values ('ffffffff-9999-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f@chess.test', 'x', now(), now(), now())
on conflict (id) do nothing;

insert into public.profiles (id, first_name, subscription_active, subscription_tier)
values ('ffffffff-9999-0000-0000-000000000006', 'Fin', true, 'premium')
on conflict (id) do update set subscription_active = true, subscription_tier = 'premium';

set local role authenticated;
set local request.jwt.claims = '{"sub":"ffffffff-9999-0000-0000-000000000006"}';

-- Checked before the tier, deliberately: telling a solo Premium subscriber they need Premium would
-- be both wrong and unfixable by them.
select throws_ok(
  $$ select public.start_chess_session() $$,
  'chess_needs_partner',
  'a board with one player is not a game, whatever they have paid'
);

-- MARK: the client cannot write moves

set local request.jwt.claims = '{"sub":"aaaaaaaa-9999-0000-0000-000000000001"}';

select throws_ok(
  $$ insert into public.game_moves (session_id, move_number, player_id, move)
     values ((select id from public.game_sessions where game_type = 'chess' and couple_id = 'cccccccc-9999-0000-0000-000000000003'),
             0, 'aaaaaaaa-9999-0000-0000-000000000001', 'e2e4') $$,
  '42501',
  NULL,
  'a player cannot write a move directly — every move goes through the edge function that validates it'
);

-- MARK: reading the board

select is(
  (select count(*)::int from public.game_moves), 0,
  'and nothing got in'
);

-- MARK: expiry covers chess as well as Connect 4

set local role postgres;

update public.game_sessions
set created_at = now() - interval '30 days'
where game_type = 'chess' and couple_id = 'cccccccc-9999-0000-0000-000000000003';

select is(
  private.expire_stale_move_games(),
  1,
  'a chess board nobody has touched in a month expires'
);

select is(
  (select status::text from public.game_sessions where game_type = 'chess' and couple_id = 'cccccccc-9999-0000-0000-000000000003'),
  'archived',
  'closed by the system rather than abandoned by a person'
);

-- And starting again gives a new board rather than the dead one.
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-9999-0000-0000-000000000001"}';

select is(
  (select (public.start_chess_session()).resumed),
  false,
  'so the next game is a new board'
);

select * from finish();
rollback;
