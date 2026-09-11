-- Starting a Word Search: which themes a plan includes, and resuming the right grid.
--
-- Three things here are only wrong in ways the app cannot show:
--
--   * A premium theme opening for a Plus couple. The client shows a lock, but the client is not the
--     enforcement — this is, and a build with the lock removed would otherwise work.
--   * A lapsed Premium subscriber keeping the premium themes. `subscription_tier` is never cleared
--     on lapse, so reading it without `subscription_active` grants them forever. This codebase has
--     made that exact mistake once already.
--   * Resume matching on couple but not on theme, which would hand somebody their half-finished
--     Travel grid when they asked for Cities — the two would displace each other permanently.

begin;
select plan(13);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-6666-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@search.test', 'x', now(), now(), now()),
  ('bbbbbbbb-6666-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@search.test', 'x', now(), now(), now()),
  ('dddddddd-6666-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'd@search.test', 'x', now(), now(), now()),
  ('eeeeeeee-6666-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'e@search.test', 'x', now(), now(), now());

insert into public.profiles (id, first_name, subscription_active, subscription_tier) values
  ('aaaaaaaa-6666-0000-0000-000000000001', 'Ada', true, 'plus'),
  ('bbbbbbbb-6666-0000-0000-000000000002', 'Mel', true, 'plus'),
  -- Solo and lapsed: the tier column still says premium, because nothing ever clears it.
  ('dddddddd-6666-0000-0000-000000000004', 'Dev', false, 'premium'),
  ('eeeeeeee-6666-0000-0000-000000000005', 'Eve', true, 'premium')
on conflict (id) do update
  set first_name = excluded.first_name,
      subscription_active = excluded.subscription_active,
      subscription_tier = excluded.subscription_tier;

insert into public.couples (id, partner_a_id, partner_b_id)
values ('cccccccc-6666-0000-0000-000000000003', 'aaaaaaaa-6666-0000-0000-000000000001', 'bbbbbbbb-6666-0000-0000-000000000002');

-- MARK: the free themes

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-6666-0000-0000-000000000001"}';

select lives_ok(
  $$ select public.start_word_search_session('travel') $$,
  'a Plus couple can play Travel'
);

select lives_ok(
  $$ select public.start_word_search_session('love') $$,
  'and Love'
);

select is(
  (select count(*)::int from public.game_sessions where game_type = 'word_search' and couple_id = 'cccccccc-6666-0000-0000-000000000003'),
  2,
  'two themes, two grids — neither displaced the other'
);

select is(
  (select is_daily from public.game_sessions where game_type = 'word_search' and couple_id = 'cccccccc-6666-0000-0000-000000000003' limit 1),
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
  (select (public.start_word_search_session('travel')).puzzle_id),
  (select r.content_id from public.game_session_rounds r
     join public.game_sessions gs on gs.id = r.session_id
    where gs.game_type = 'word_search' and r.theme = 'travel'
      and gs.couple_id = 'cccccccc-6666-0000-0000-000000000003'),
  'and hands back that grid''s own id, not the other theme''s'
);

select is(
  (select count(*)::int from public.game_sessions where game_type = 'word_search' and couple_id = 'cccccccc-6666-0000-0000-000000000003'),
  2,
  'resuming started nothing new'
);

-- The partner is handed the same grid, which is the whole point of a shared puzzle.
set local request.jwt.claims = '{"sub":"bbbbbbbb-6666-0000-0000-000000000002"}';

select is(
  (select (public.start_word_search_session('love')).resumed),
  true,
  'the partner gets the couple''s grid rather than one of their own'
);

-- MARK: the premium themes

set local request.jwt.claims = '{"sub":"aaaaaaaa-6666-0000-0000-000000000001"}';

select throws_ok(
  $$ select public.start_word_search_session('cities') $$,
  'This theme requires Premium',
  'a Plus couple is refused a premium theme'
);

select throws_ok(
  $$ select public.start_word_search_session('music') $$,
  'This theme requires Premium',
  'all four of them'
);

set local request.jwt.claims = '{"sub":"eeeeeeee-6666-0000-0000-000000000005"}';

select lives_ok(
  $$ select public.start_word_search_session('cities') $$,
  'a Premium player gets them'
);

-- MARK: a lapsed subscription keeps only the free themes

set local request.jwt.claims = '{"sub":"dddddddd-6666-0000-0000-000000000004"}';

select lives_ok(
  $$ select public.start_word_search_session('travel') $$,
  'a lapsed subscriber still plays the free themes'
);

select throws_ok(
  $$ select public.start_word_search_session('nature') $$,
  'This theme requires Premium',
  'but not the premium ones, however much their stale tier column says otherwise'
);

select * from finish();
rollback;
