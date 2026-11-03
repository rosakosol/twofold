-- submit_support_request_with_thread returns the conversation a request landed in (20261121000200,
-- SITE-18).
--
-- The website's receipt quoted a reference made up on the spot. It matched nothing in the console,
-- which lists conversations (support_threads) rather than requests. So the route needs the thread
-- id back. submit_support_request returns only the request id, and the iOS app's
-- submit-help-message function calls it, so that contract is pinned here too: same arguments, same
-- scalar uuid, still the request's own id.

begin;
select plan(13);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values ('5a5a5a5a-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
        'authenticated', 'kit@threadref.test', 'x', now(), now(), now());
insert into public.profiles (id, first_name) values ('5a5a5a5a-0000-4000-8000-000000000001', 'Kit')
on conflict (id) do update set first_name = excluded.first_name;

-- ---------------------------------------------------------------------------
-- The old function's contract is unchanged
-- ---------------------------------------------------------------------------

select is(
  pg_get_function_result('public.submit_support_request(text, text, text, text, text, text, uuid, text)'::regprocedure),
  'uuid',
  'submit_support_request still returns a single uuid'
);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"5a5a5a5a-0000-4000-8000-000000000001","role":"authenticated"}', true);
create temporary table old_call on commit drop as
  select public.submit_support_request('Bug Report', 'From the app', 'Old path', null, null, 'app') as id;
reset role;

select is(
  (select profile_id from public.support_requests where id = (select id from old_call)),
  '5a5a5a5a-0000-4000-8000-000000000001'::uuid,
  'and that uuid is still the request it filed'
);

-- ---------------------------------------------------------------------------
-- The website's path: the service role, nobody signed in
-- ---------------------------------------------------------------------------

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
create temporary table web_call on commit drop as
  select * from public.submit_support_request_with_thread(
    p_category => 'Bug Report', p_message => 'The widget is blank.', p_email => 'visitor@threadref.test',
    p_name => 'Sam', p_source => 'web');
reset role;

select is((select count(*)::int from web_call), 1, 'it returns one row');
select is(
  (select r.thread_id from public.support_requests r where r.id = (select request_id from web_call)),
  (select thread_id from web_call),
  'whose thread_id is the thread the request was filed in'
);
select ok(
  exists (select 1 from public.support_threads t where t.id = (select thread_id from web_call)),
  'which is a real conversation in the console'
);
select is(
  (select row(email, source, profile_id)::text from public.support_requests where id = (select request_id from web_call)),
  row('visitor@threadref.test', 'web', null::uuid)::text,
  'filed exactly as the old function files it'
);

-- A second message from the same visitor is its own conversation, so its own reference.
set local role service_role;
create temporary table web_again on commit drop as
  select * from public.submit_support_request_with_thread(
    p_category => 'Bug Report', p_message => 'Still blank.', p_email => 'visitor@threadref.test', p_source => 'web');
reset role;
select isnt((select thread_id from web_again), (select thread_id from web_call),
  'an unverified visitor writing again starts a new conversation, as before');

-- ---------------------------------------------------------------------------
-- A signed-in caller, joining an existing conversation by subject
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"5a5a5a5a-0000-4000-8000-000000000001","role":"authenticated"}', true);
create temporary table app_call on commit drop as
  select * from public.submit_support_request_with_thread('Bug Report', 'Following up', 'Old path', null, null, 'app');
reset role;

select is(
  (select thread_id from app_call),
  (select thread_id from public.support_requests where id = (select id from old_call)),
  'a follow-up under the same subject returns the conversation it joined'
);

-- ---------------------------------------------------------------------------
-- Validation and grants are the old function's
-- ---------------------------------------------------------------------------

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select throws_ok(
  $$ select * from public.submit_support_request_with_thread('Bug Report', 'x', null, 'not an address', null, 'web') $$,
  '22023', 'a single valid email address is required',
  'it refuses what the old function refuses'
);
reset role;

select ok(not has_function_privilege('anon',
  'public.submit_support_request_with_thread(text, text, text, text, text, text, uuid, text)', 'EXECUTE'),
  'anon cannot call it');
select ok(has_function_privilege('authenticated',
  'public.submit_support_request_with_thread(text, text, text, text, text, text, uuid, text)', 'EXECUTE'),
  'a signed-in caller can');
select ok(has_function_privilege('service_role',
  'public.submit_support_request_with_thread(text, text, text, text, text, text, uuid, text)', 'EXECUTE'),
  'and so can the website''s service role');
select ok(not has_function_privilege('anon',
  'public.submit_support_request(text, text, text, text, text, text, uuid, text)', 'EXECUTE'),
  'and the old one is still closed to anon');

select * from finish();
rollback;
