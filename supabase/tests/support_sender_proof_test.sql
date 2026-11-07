-- What proves who wrote to support, and how much one account can file (20261124000600).

begin;
select plan(19);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', email, 'x', now(), now(), now()
from (values
  ('a7a7a7a7-0000-4000-8000-000000000001'::uuid, 'support@proof.test'),
  ('a7a7a7a7-0000-4000-8000-000000000002'::uuid, 'victim@proof.test'),
  ('a7a7a7a7-0000-4000-8000-000000000003'::uuid, 'member@proof.test')
) as v(id, email);

insert into public.feedback_admins (profile_id, role) values ('a7a7a7a7-0000-4000-8000-000000000001', 'support');

-- The attack: a website request under the attacker's own address, then mail on its token with a
-- forged From.
select public.submit_support_request('Other', 'hello', null, 'attacker@else.test', 'A', 'web');

create temp table attacker_thread on commit drop as
  select id, token from public.support_threads where email = 'attacker@else.test';
grant select on attacker_thread to authenticated, service_role;

select public.ingest_support_email(
  '<forged@x>', 'victim@proof.test', 'Victim', 'please delete my account', 'delete it',
  now(), 'support+t' || (select token from attacker_thread) || '@twofoldapp.com.au');

select is((select thread_id from public.support_requests where message_id = '<forged@x>'),
  (select id from attacker_thread), 'a forged sender on a token still files in that conversation');
select is((select profile_id from public.support_requests where message_id = '<forged@x>'), null,
  'but the message links to nobody');
select is((select sender_proof from public.support_requests where message_id = '<forged@x>'), null,
  'and proves nothing');
select is((select profile_id from public.support_threads where id = (select id from attacker_thread)), null,
  'the conversation does not take on the victim''s account');

-- The owner of the conversation's address replying on its token has shown they can read it.
select public.ingest_support_email(
  '<real@x>', 'attacker@else.test', 'A', null, 'still me',
  now(), 'support+t' || (select token from attacker_thread) || '@twofoldapp.com.au');
select is((select sender_proof from public.support_requests where message_id = '<real@x>'), 'mailbox',
  'a reply on the token from the conversation''s address is proof');

-- A website request naming the victim, who then answers the receipt: their account, proven.
select public.submit_support_request('Other', 'typed their address', null, 'victim@proof.test', 'V', 'web');
create temp table victim_thread on commit drop as
  select id, token from public.support_threads where email = 'victim@proof.test' order by created_at desc limit 1;
grant select on victim_thread to authenticated;
select public.ingest_support_email(
  '<owner@x>', 'VICTIM@proof.test', 'V', null, 'yes that was me',
  now(), 'support+t' || (select token from victim_thread) || '@twofoldapp.com.au');
select is((select sender_proof from public.support_requests where message_id = '<owner@x>'), 'mailbox',
  'case does not matter');
select is((select profile_id from public.support_requests where message_id = '<owner@x>'),
  'a7a7a7a7-0000-4000-8000-000000000002'::uuid, 'and the message links to their account');

-- Plain mail with no token: linked as before, but only as a claim.
select public.ingest_support_email('<plain@x>', 'victim@proof.test', 'V', 'new thing', 'hi');
select is((select profile_id from public.support_requests where message_id = '<plain@x>'),
  'a7a7a7a7-0000-4000-8000-000000000002'::uuid, 'plain mail is still matched by address');
select is((select sender_proof from public.support_requests where message_id = '<plain@x>'), null,
  'and proves nothing');

-- A token nobody issued is no proof.
select public.ingest_support_email('<badtoken@x>', 'victim@proof.test', 'V', 'other', 'hi',
  now(), 'support+tnotarealtoken@twofoldapp.com.au');
select is((select sender_proof from public.support_requests where message_id = '<badtoken@x>'), null,
  'nor does a token that matches no conversation');

-- The console is told.
set local role authenticated;
select set_config('request.jwt.claims',
  '{"aal":"aal2","sub":"a7a7a7a7-0000-4000-8000-000000000001","role":"authenticated"}', true);
select is(
  (select r.sender_proof from public.admin_support_requests(null, 200) r where r.message = 'still me'), 'mailbox',
  'the console reads the proof');
select is(
  (select r.thread_email from public.admin_support_requests(null, 200) r where r.message = 'delete it'), 'attacker@else.test',
  'and the conversation''s address, to compare with the sender');
reset role;

-- A signed-in member.
create function pg_temp.file(p_subject text) returns uuid language sql as $$
  select public.submit_support_request('Other', 'text', p_subject, 'ignored@else.test', repeat('n', 500), 'app');
$$;
grant execute on function pg_temp.file(text) to authenticated;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a7a7a7a7-0000-4000-8000-000000000003","role":"authenticated"}', true);

create temp table first_filed on commit drop as select pg_temp.file(repeat('s', 500)) as id;
reset role;
select is((select sender_proof from public.support_requests where id = (select id from first_filed)), 'account',
  'an app message is proven by its session');
select is((select email from public.support_requests where id = (select id from first_filed)), 'member@proof.test',
  'and keeps the account''s own address');
select is((select length(subject) from public.support_requests where id = (select id from first_filed)), 200,
  'a long subject is cut to 200');
select is((select length(name) from public.support_requests where id = (select id from first_filed)), 200,
  'a long name is cut to 200');
set local role authenticated;

do $$ begin for i in 2..20 loop perform pg_temp.file('s' || i); end loop; end $$;
select throws_ok($$ select pg_temp.file('one too many') $$, 'P0001', 'support_request_limit',
  'the twenty-first in an hour is refused');
select throws_ok(
  $$ select public.submit_support_request_with_thread('Report Abuse', 'x', 'other route', null, null, 'app') $$,
  'P0001', 'support_request_limit', 'by the other entry point as well');

-- The website's calls have no user, and keep the route's own limits.
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select isnt(public.submit_support_request('Other', 'from the form', null, 'visitor@else.test', 'V', 'web'), null,
  'the service role is not counted against anybody');
reset role;

select * from finish();
rollback;
