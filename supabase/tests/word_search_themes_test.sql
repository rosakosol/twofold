-- Starting a Word Search: who may play it at all, and resuming the right grid.
--
-- The theme split is gone. Travel and Love were free while Word Search was on every plan; since
-- 20261111000700 the whole game is Premium, so there is one gate rather than six answers. This
-- file used to assert the opposite.
--
-- Rewritten rather than deleted, because everything besides the tier still holds, and each of
-- those is still only wrong in ways the app cannot show:
--
--   * The game opening for a Plus couple. The client shows a lock, but the client is not the
--     enforcement — this is, and a build with the lock removed would otherwise work.
--   * A lapsed Premium subscriber keeping it. `subscription_tier` is never cleared on lapse, so
--     reading it without `subscription_active` grants them forever. This codebase has made that
--     exact mistake once already.
--   * Resume matching on couple but not on theme, which would hand somebody their half-finished
--     Travel grid when they asked for Cities — the two would displace each other permanently.
--
-- The couple that exercises resuming is Premium now, because a Plus one can no longer create the
-- grids those assertions are about. The refusals get a Plus couple of their own, so the coupled
-- path through `couple_effective_tier` stays covered rather than only the solo one.

begin;
select plan(10);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-6666-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@search.test', 'x', now(), now(), now()),
  ('bbbbbbbb-6666-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@search.test', 'x', now(), now(), now()),
  ('dddddddd-6666-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'd@search.test', 'x', now(), now(), now()),
  ('eeeeeeee-6666-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'e@search.test', 'x', now(), now(), now()),
  ('ffffffff-6666-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f@search.test', 'x', now(), now(), now()),
  ('99999999-6666-0000-0000-000000000007', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'g@search.test', 'x', now(), now(), now());

insert into public.profiles (id, first_name, subscription_active, subscription_tier) values
  -- The Premium couple, who can actually make the grids the resume assertions are about.
  ('aaaaaaaa-6666-0000-0000-000000000001', 'Ada', true, 'premium'),
  ('bbbbbbbb-6666-0000-0000-000000000002', 'Mel', true, 'premium'),
  -- Solo and lapsed: the tier column still says premium, because nothing ever clears it.
  ('dddddddd-6666-0000-0000-000000000004', 'Dev', false, 'premium'),
  ('eeeeeeee-6666-0000-0000-000000000005', 'Eve', true, 'premium'),
  -- The Plus couple, who may not play at all.
  ('ffffffff-6666-0000-0000-000000000006', 'Fin', true, 'plus'),
  ('99999999-6666-0000-0000-000000000007', 'Gus', true, 'plus')
on conflict (id) do update
  set first_name = excluded.first_name,
      subscription_active = excluded.subscription_active,
      subscription_tier = excluded.subscription_tier;

insert into public.couples (id, partner_a_id, partner_b_id)
values
  ('cccccccc-6666-0000-0000-000000000003', 'aaaaaaaa-6666-0000-0000-000000000001', 'bbbbbbbb-6666-0000-0000-000000000002'),
  ('cccccccc-6666-0000-0000-000000000008', 'ffffffff-6666-0000-0000-000000000006', '99999999-6666-0000-0000-000000000007');

-- MARK: a Plus couple is refused the whole game

set local role authenticated;
set local request.jwt.claims = '{"sub":"ffffffff-6666-0000-0000-000000000006"}';

select throws_ok(
  $$ select public.start_word_search_session('travel') $$,
  'word_search_requires_premium',
  'a Plus couple is refused Travel, which used to be free on every plan'
);

select throws_ok(
  $$ select public.start_word_search_session('cities') $$,
  'word_search_requires_premium',
  'and every other theme with it — the gate is the game, not the theme'
);

-- MARK: a Premium couple plays, and each theme keeps its own grid

set local request.jwt.claims = '{"sub":"aaaaaaaa-6666-0000-0000-000000000001"}';

select lives_ok(
  $$ select public.start_word_search_session('travel') $$,
  'a Premium couple plays'
);

select lives_ok(
  $$ select public.start_word_search_session('cities') $$,
  'and a second theme alongside the first'
);

select is(
  (select count(*)::int from public.game_sessions where game_type = 'word_search' and couple_id = 'cccccccc-6666-0000-0000-000000000003'),
  2,
  'two themes, two grids — neither displaced the other'
);

select is(
  (select bool_or(is_daily) from public.game_sessions where game_type = 'word_search' and couple_id = 'cccccccc-6666-0000-0000-000000000003'),
  false,
  'a word search is never a daily session, so it can never touch the streak'
);

-- MARK: resuming matches on theme, not just on the couple

select is(
  (select (public.start_word_search_session('travel')).resumed),
  true,
  'asking for Travel again resumes the Travel grid'
);

select is(
  (select count(*)::int from public.game_sessions where game_type = 'word_search' and couple_id = 'cccccccc-6666-0000-0000-000000000003'),
  2,
  'resuming started nothing new'
);

-- The partner is handed the same grid, which is the whole point of a shared puzzle.
set local request.jwt.claims = '{"sub":"bbbbbbbb-6666-0000-0000-000000000002"}';

select is(
  (select (public.start_word_search_session('cities')).resumed),
  true,
  'the partner gets the couple''s grid rather than one of their own'
);

-- MARK: a lapsed subscription buys nothing

set local request.jwt.claims = '{"sub":"dddddddd-6666-0000-0000-000000000004"}';

select throws_ok(
  $$ select public.start_word_search_session('nature') $$,
  'word_search_requires_premium',
  'a lapsed subscriber is refused, however much their stale tier column says otherwise'
);

select * from finish();
rollback;
