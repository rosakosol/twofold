-- 18+ decks exist for a couple only once both partners have opted in, and stop existing the moment
-- either opts out. Checked through the read policies and through start_deck_session, which is a
-- definer and would otherwise build a session from a deck the couple cannot see.

begin;
select plan(17);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', email, 'x', now(), now(), now()
from (values
  ('dddddddd-aaaa-0000-0000-000000000001'::uuid, 'a@adult.test'),
  ('dddddddd-aaaa-0000-0000-000000000002'::uuid, 'b@adult.test'),
  ('dddddddd-aaaa-0000-0000-000000000003'::uuid, 'solo@adult.test'),
  ('dddddddd-aaaa-0000-0000-000000000004'::uuid, 'admin@adult.test')
) as v(id, email);

insert into public.profiles (id, first_name) values
  ('dddddddd-aaaa-0000-0000-000000000001', 'Ana'),
  ('dddddddd-aaaa-0000-0000-000000000002', 'Ben'),
  ('dddddddd-aaaa-0000-0000-000000000003', 'Sol'),
  ('dddddddd-aaaa-0000-0000-000000000004', 'Adm')
on conflict (id) do update set first_name = excluded.first_name;

insert into public.feedback_admins (profile_id, role) values ('dddddddd-aaaa-0000-0000-000000000004', 'content');

insert into public.couples (id, partner_a_id, partner_b_id, status) values
  ('dddddddd-aaaa-cccc-0000-00000000000a', 'dddddddd-aaaa-0000-0000-000000000001', 'dddddddd-aaaa-0000-0000-000000000002', 'active');

-- Plus, so only the 18+ gate is under test.
insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count, adult) values
  ('dddddddd-aaaa-dddd-0000-00000000000a', 'After Dark', 'more_likely', 'Test 18+ deck', 'x', 'plus', 999, true, 0, true),
  ('dddddddd-aaaa-dddd-0000-00000000000b', 'Starters', 'more_likely', 'Test ordinary deck', 'x', 'plus', 999, true, 0, false);
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values
  ('Test 18+ prompt', true, 'plus', 'After Dark', 'dddddddd-aaaa-dddd-0000-00000000000a'),
  ('Test ordinary prompt', true, 'plus', 'Starters', 'dddddddd-aaaa-dddd-0000-00000000000b');

set local role authenticated;

-- ---------------------------------------------------------------------------
-- Nobody has opted in
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'dddddddd-aaaa-0000-0000-000000000001', true);

select is((select count(*)::int from public.game_decks where id = 'dddddddd-aaaa-dddd-0000-00000000000a'), 0,
  'an 18+ deck is invisible before anyone opts in');
select is((select count(*)::int from public.more_likely_prompts where prompt = 'Test 18+ prompt'), 0,
  'and so are its questions');
select is((select count(*)::int from public.more_likely_prompts where prompt = 'Test ordinary prompt'), 1,
  'ordinary questions are unaffected');
select throws_ok($$ select public.start_deck_session('dddddddd-aaaa-dddd-0000-00000000000a') $$,
  null, 'This deck needs both partners to turn on 18+ questions', 'and no session can be started from it');

select throws_ok($$ update public.profiles set adult_content_opt_in_at = now() where id = 'dddddddd-aaaa-0000-0000-000000000001' $$,
  '42501', null, 'the opt-in cannot be written directly');

-- ---------------------------------------------------------------------------
-- One partner opts in
-- ---------------------------------------------------------------------------

select public.set_adult_content_opt_in(true);

select results_eq($$ select me, partner, has_partner from public.adult_content_status() $$,
  $$ values (true, false, true) $$, 'status shows I am in and my partner is not');
select is((select count(*)::int from public.game_decks where id = 'dddddddd-aaaa-dddd-0000-00000000000a'), 0,
  'one partner opting in is not enough');
select throws_ok($$ select public.start_deck_session('dddddddd-aaaa-dddd-0000-00000000000a') $$,
  null, 'This deck needs both partners to turn on 18+ questions', 'not for a session either');

-- ---------------------------------------------------------------------------
-- Both opt in
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'dddddddd-aaaa-0000-0000-000000000002', true);
select results_eq($$ select me, partner, has_partner from public.adult_content_status() $$,
  $$ values (false, true, true) $$, 'my partner sees that I have opted in');
select public.set_adult_content_opt_in(true);

select is((select count(*)::int from public.game_decks where id = 'dddddddd-aaaa-dddd-0000-00000000000a'), 1,
  'with both in, the deck appears');
select is((select count(*)::int from public.more_likely_prompts where prompt = 'Test 18+ prompt'), 1,
  'and its questions');
select isnt(public.start_deck_session('dddddddd-aaaa-dddd-0000-00000000000a'), null,
  'and a session can be started');

select set_config('request.jwt.claim.sub', 'dddddddd-aaaa-0000-0000-000000000001', true);
select is((select count(*)::int from public.more_likely_prompts where prompt = 'Test 18+ prompt'), 1,
  'for both partners');

-- ---------------------------------------------------------------------------
-- Either opting out closes it for both
-- ---------------------------------------------------------------------------

select public.set_adult_content_opt_in(false);
select set_config('request.jwt.claim.sub', 'dddddddd-aaaa-0000-0000-000000000002', true);
select is((select count(*)::int from public.more_likely_prompts where prompt = 'Test 18+ prompt'), 0,
  'one partner opting out hides it from the other at once');

-- ---------------------------------------------------------------------------
-- Alone, and as an admin
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'dddddddd-aaaa-0000-0000-000000000003', true);
select public.set_adult_content_opt_in(true);
select is((select count(*)::int from public.game_decks where id = 'dddddddd-aaaa-dddd-0000-00000000000a'), 0,
  'someone without a partner cannot open it alone');

select set_config('request.jwt.claim.sub', 'dddddddd-aaaa-0000-0000-000000000004', true);
select is((select count(*)::int from public.game_decks where id = 'dddddddd-aaaa-dddd-0000-00000000000a'), 1,
  'the content console still sees 18+ decks');
select is((select count(*)::int from public.more_likely_prompts where prompt = 'Test 18+ prompt'), 1,
  'and their questions');

select * from finish();
rollback;
