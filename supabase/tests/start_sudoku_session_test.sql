-- ---------------------------------------------------------------------------
-- start_sudoku_session: one puzzle, derived twice, from an id neither device chose
-- ---------------------------------------------------------------------------
--
-- The sudoku itself never leaves the client. The server picks a uuid; both partners run it through
-- `SudokuGenerator` and get the same grid. So the property this RPC has to hold is narrow and
-- absolute: for one difficulty, a couple gets ONE `puzzle_id`, and both of them get it. Hand back
-- two and there is no failure — two people simply solve different grids and compare results that
-- mean nothing to each other. Nothing logs, nothing raises.
--
-- That is what the first block asserts, from both sides of the couple.
--
-- The second block is the tier gate, and one of its assertions is a regression: the solo branch
-- originally read `subscription_tier` without `subscription_active`, which is precisely the leak
-- 20260912000000 was written to close in `get_daily_question_session` — `subscription_tier` is
-- never cleared when a subscription lapses, so a stale 'premium' sits on the profile forever. The
-- test below fails against that first version.

begin;
select plan(20);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-5000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ann@sudoku.test',   'x', now(), now(), now()),
  ('bbbbbbbb-5000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ben@sudoku.test',   'x', now(), now(), now()),
  ('cccccccc-5000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'cara@sudoku.test',  'x', now(), now(), now()),
  ('dddddddd-5000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'dan@sudoku.test',   'x', now(), now(), now()),
  ('eeeeeeee-5000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'lapsed@sudoku.test','x', now(), now(), now()),
  ('ffffffff-5000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'solo@sudoku.test',  'x', now(), now(), now());

-- Ann + Ben: a couple on plus. Cara + Dan: a couple where only Cara pays, and she pays for premium
-- — the couple-wide OR is what gives Dan the hard difficulties too.
insert into public.couples (id, partner_a_id, partner_b_id, status)
values
  ('11111111-5000-0000-0000-00000000000a', 'aaaaaaaa-5000-0000-0000-000000000001', 'bbbbbbbb-5000-0000-0000-000000000002', 'active'),
  ('22222222-5000-0000-0000-00000000000b', 'cccccccc-5000-0000-0000-000000000003', 'dddddddd-5000-0000-0000-000000000004', 'active');

-- Written as postgres: 20260915000000 blocks clients from setting these columns.
update public.profiles set subscription_active = true,  subscription_tier = 'plus'
  where id in ('aaaaaaaa-5000-0000-0000-000000000001', 'bbbbbbbb-5000-0000-0000-000000000002',
               'dddddddd-5000-0000-0000-000000000004');
update public.profiles set subscription_active = true,  subscription_tier = 'premium'
  where id in ('cccccccc-5000-0000-0000-000000000003', 'ffffffff-5000-0000-0000-000000000006');
-- Premium recorded, subscription over. The whole point of the regression assertion below.
update public.profiles set subscription_active = false, subscription_tier = 'premium'
  where id = 'eeeeeeee-5000-0000-0000-000000000005';

-- ---------------------------------------------------------------------------
-- One puzzle per couple per difficulty
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-5000-0000-0000-000000000001","role":"authenticated"}';

select set_config('test.s1', (select session_id::text from public.start_sudoku_session('easy')), true);
select set_config('test.p1', (select puzzle_id::text  from public.start_sudoku_session('easy')), true);

select isnt(current_setting('test.p1'), '', 'a puzzle id comes back');

select is(
  (select resumed from public.start_sudoku_session('easy')),
  true,
  'a second call resumes rather than starting again'
);

select is(
  (select session_id from public.start_sudoku_session('easy')),
  current_setting('test.s1')::uuid,
  'and resumes the same session'
);

select is(
  (select count(*)::int from public.game_sessions
    where game_type = 'sudoku' and couple_id = '11111111-5000-0000-0000-00000000000a'),
  1,
  'so three calls left one session row, not three'
);

-- The property the whole design rests on.
set local request.jwt.claims = '{"sub":"bbbbbbbb-5000-0000-0000-000000000002","role":"authenticated"}';
select is(
  (select puzzle_id from public.start_sudoku_session('easy')),
  current_setting('test.p1')::uuid,
  'the partner derives their grid from the SAME puzzle id — the one thing that cannot differ'
);
select is(
  (select session_id from public.start_sudoku_session('easy')),
  current_setting('test.s1')::uuid,
  'and joins the couple''s session rather than opening a parallel one'
);

-- ---------------------------------------------------------------------------
-- Difficulties do not displace each other
-- ---------------------------------------------------------------------------

set local request.jwt.claims = '{"sub":"aaaaaaaa-5000-0000-0000-000000000001","role":"authenticated"}';
select set_config('test.p_med', (select puzzle_id::text from public.start_sudoku_session('medium')), true);

select isnt(
  current_setting('test.p_med')::uuid,
  current_setting('test.p1')::uuid,
  'starting a Medium while the Easy is unfinished gives a different puzzle'
);
select is(
  (select count(*)::int from public.game_sessions
    where game_type = 'sudoku' and couple_id = '11111111-5000-0000-0000-00000000000a'
      and status in ('active', 'waiting_for_partner')),
  2,
  'and leaves the Easy open alongside it'
);

-- A finished puzzle is not reopened — that would overwrite the record of the first solve.
reset role;
update public.game_sessions set status = 'completed'
  where game_type = 'sudoku' and couple_id = '11111111-5000-0000-0000-00000000000a'
    and id = current_setting('test.s1')::uuid;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-5000-0000-0000-000000000001","role":"authenticated"}';

select isnt(
  (select session_id from public.start_sudoku_session('easy')),
  current_setting('test.s1')::uuid,
  'a completed puzzle starts a fresh one instead of reopening the solved grid'
);

-- ---------------------------------------------------------------------------
-- The tier gate
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select public.start_sudoku_session('medium')$$,
  'Easy and Medium are free'
);
select throws_ok(
  $$select public.start_sudoku_session('hard')$$,
  'P0001', 'This difficulty requires Premium',
  'a plus couple is refused Hard'
);
select throws_ok(
  $$select public.start_sudoku_session('expert')$$,
  'P0001', 'This difficulty requires Premium',
  'and Expert'
);

-- Dan pays for nothing; Cara's premium covers him. Without this, the two refusals above would pass
-- against a function that simply refused Hard to everybody.
set local request.jwt.claims = '{"sub":"dddddddd-5000-0000-0000-000000000004","role":"authenticated"}';
select lives_ok(
  $$select public.start_sudoku_session('expert')$$,
  'a partner on a premium couple gets Expert without paying themselves'
);

-- The regression. `subscription_tier` still says premium; the subscription ended.
set local request.jwt.claims = '{"sub":"eeeeeeee-5000-0000-0000-000000000005","role":"authenticated"}';
select throws_ok(
  $$select public.start_sudoku_session('expert')$$,
  'P0001', 'This difficulty requires Premium',
  'a solo user whose premium lapsed is refused, despite the stale tier on their profile'
);

-- And the control, so the assertion above is about lapsing rather than about being solo.
set local request.jwt.claims = '{"sub":"ffffffff-5000-0000-0000-000000000006","role":"authenticated"}';
select lives_ok(
  $$select public.start_sudoku_session('expert')$$,
  'a solo user with a live premium subscription still gets Expert'
);

select throws_ok(
  $$select public.start_sudoku_session('impossible')$$,
  'P0001', 'Unknown difficulty',
  'an unknown difficulty is refused rather than quietly stored'
);

-- ---------------------------------------------------------------------------
-- Who may call it
-- ---------------------------------------------------------------------------
--
-- `revoke ... from public`, not `from anon, authenticated`. Functions carry an EXECUTE grant to
-- PUBLIC by default, and revoking from the two named roles leaves that default standing — the
-- function stays callable by exactly the roles the revoke was meant to stop.

reset role;
select ok(
  not has_function_privilege('anon', 'public.start_sudoku_session(text)', 'execute'),
  'anon cannot call it'
);
select ok(
  has_function_privilege('authenticated', 'public.start_sudoku_session(text)', 'execute'),
  'authenticated can'
);

-- ---------------------------------------------------------------------------
-- Where the difficulty is kept
-- ---------------------------------------------------------------------------
--
-- Its own column, not `discussion_status`. That column is `text` in Postgres but a two-case enum
-- in the client (`DiscussionRoundStatus`), so a round holding 'hard' fails to decode and takes
-- the whole `fetchGameSession` down with it — the puzzle plays, then never opens again. The first
-- version of this RPC did exactly that. These two assertions are the pair: the difficulty is
-- somewhere it can be read, and it is not somewhere it cannot.

select is(
  (select r.difficulty from public.game_session_rounds r
   join public.game_sessions s on s.id = r.session_id
   where s.game_type = 'sudoku' and s.couple_id = '11111111-5000-0000-0000-00000000000a'
     and r.difficulty = 'medium' limit 1),
  'medium',
  'the difficulty is stored in its own column'
);

select is(
  (select count(*)::int from public.game_session_rounds r
   join public.game_sessions s on s.id = r.session_id
   where s.game_type = 'sudoku' and r.discussion_status is not null),
  0,
  'and never in discussion_status, which the client decodes as a two-case enum'
);

select * from finish();
rollback;
