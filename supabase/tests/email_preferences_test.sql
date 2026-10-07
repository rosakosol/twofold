-- Email preferences and unsubscribe links (20261112000000).
--
-- What has to hold: a link's token changes only its own address; a signed-in person changes only
-- their own; leaving the waitlist really removes the address; product news is opt-in; and the
-- feedback confirmation goes once, to the author, and not to someone who turned it off.

begin;
select plan(19);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', email, 'x', now(), now(), now()
from (values
  ('aaaaaaaa-7777-0000-0000-000000000001'::uuid, 'Sam@Example.com'),
  ('bbbbbbbb-7777-0000-0000-000000000002'::uuid, 'alex@example.com')
) as v(id, email);
insert into public.profiles (id, first_name) values
  ('aaaaaaaa-7777-0000-0000-000000000001', 'Sam'),
  ('bbbbbbbb-7777-0000-0000-000000000002', 'Alex')
on conflict (id) do update set first_name = excluded.first_name;

-- ---------------------------------------------------------------------------
-- Joining the waitlist, as a visitor
-- ---------------------------------------------------------------------------

set local role anon;

select is((select status from public.join_android_waitlist(' Jo@Example.com ')), 'joined', 'a new address joins');
select is((select status from public.join_android_waitlist('jo@example.com')), 'exists', 'the same address, any case, already exists');
select throws_ok($$ select * from public.join_android_waitlist('not an email') $$, '22023', null, 'a non-address is refused');
select throws_ok($$ select * from public.email_preferences $$, '42501', null, 'the table itself is not readable');

reset role;
select is((select count(*)::int from public.waitlist_signups where email = 'jo@example.com'), 1, 'stored once, lower case');
select is((select product_news from public.email_preferences where email = 'jo@example.com'), false, 'product news is opt-in');

-- ---------------------------------------------------------------------------
-- From an email link
-- ---------------------------------------------------------------------------

create temporary table jo as select token from public.email_preferences where email = 'jo@example.com';
grant select on jo to anon;
set local role anon;

select is((select masked_email from public.email_preferences_by_token((select token from jo))), 'j•••@example.com',
  'the page shows only a masked address');
select ok(public.set_email_preference_by_token((select token from jo), 'android_waitlist', false), 'leaving the waitlist');
select ok(not public.set_email_preference_by_token(gen_random_uuid(), 'android_waitlist', false), 'an unknown token changes nothing');
select throws_ok($$ select public.set_email_preference_by_token((select token from jo), 'all', true) $$, '22023', null,
  'opting into everything at once is refused');

reset role;
select is((select count(*)::int from public.waitlist_signups where email = 'jo@example.com'), 0, 'leaving really removes the address');

-- ---------------------------------------------------------------------------
-- Signed in
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-7777-0000-0000-000000000001"}';

select is((select email from public.my_email_preferences()), 'sam@example.com', 'my preferences are my own address');
select lives_ok($$ select public.set_my_email_preference('product_news', true) $$, 'turning product news on');
select is((select product_news from public.my_email_preferences()), true, 'and it stays on');

-- ---------------------------------------------------------------------------
-- Feedback received
-- ---------------------------------------------------------------------------

reset role;
insert into public.feature_requests (id, title, slug, category, author_id) values
  ('cccccccc-7777-0000-0000-000000000001', 'Shared packing lists', 'shared-packing-lists', 'general', 'aaaaaaaa-7777-0000-0000-000000000001');

set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-7777-0000-0000-000000000002"}';
select is((select count(*)::int from public.claim_feedback_confirmation('cccccccc-7777-0000-0000-000000000001')), 0,
  'someone else cannot claim my confirmation');

set local request.jwt.claims = '{"sub":"aaaaaaaa-7777-0000-0000-000000000001"}';
select is((select title from public.claim_feedback_confirmation('cccccccc-7777-0000-0000-000000000001')), 'Shared packing lists',
  'the author gets the confirmation');
select is((select count(*)::int from public.claim_feedback_confirmation('cccccccc-7777-0000-0000-000000000001')), 0,
  'and only once');

reset role;
insert into public.feature_requests (id, title, slug, category, author_id) values
  ('cccccccc-7777-0000-0000-000000000002', 'Time zone overlap', 'time-zone-overlap', 'general', 'aaaaaaaa-7777-0000-0000-000000000001');
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-7777-0000-0000-000000000001"}';
select public.set_my_email_preference('feedback_updates', false);
select is((select count(*)::int from public.claim_feedback_confirmation('cccccccc-7777-0000-0000-000000000002')), 0,
  'not sent to someone who turned feedback updates off');

reset role;
set local role anon;
select throws_ok($$ select * from public.my_email_preferences() $$, '42501', null, 'a visitor has no preferences of their own');

select * from finish();
rollback;
