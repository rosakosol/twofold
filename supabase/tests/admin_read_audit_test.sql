-- Console reads are logged, limited per admin, and the log reads by actor (20261124000700).

begin;
select plan(19);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', email, 'x', now(), now(), now()
from (values
  ('b8b8b8b8-0000-4000-8000-000000000001'::uuid, 'reader@audit.test'),
  ('b8b8b8b8-0000-4000-8000-000000000002'::uuid, 'member@audit.test')
) as v(id, email);

insert into public.feedback_admins (profile_id, role) values ('b8b8b8b8-0000-4000-8000-000000000001', 'support');

create function pg_temp.as_admin() returns void language sql as $$
  select set_config('request.jwt.claims',
    '{"aal":"aal2","sub":"b8b8b8b8-0000-4000-8000-000000000001","role":"authenticated"}', true);
$$;
create function pg_temp.as_member() returns void language sql as $$
  select set_config('request.jwt.claims',
    '{"aal":"aal1","sub":"b8b8b8b8-0000-4000-8000-000000000002","role":"authenticated"}', true);
$$;
grant execute on function pg_temp.as_admin() to authenticated;
grant execute on function pg_temp.as_member() to authenticated;

create function pg_temp.reads(p_action text) returns bigint language sql as $$
  select count(*) from private.admin_audit_log
  where actor_id = 'b8b8b8b8-0000-4000-8000-000000000001' and action = p_action;
$$;

-- The originals are out of reach.
select ok(not has_function_privilege('authenticated', 'private.admin_list_accounts_unlogged(integer, integer)', 'execute'),
  'the unlogged account list cannot be called directly');
select ok(not has_function_privilege('authenticated', 'private.admin_support_requests_unlogged(text, integer)', 'execute'),
  'nor the unlogged support queue');

set local role authenticated;
select pg_temp.as_admin();

select ok((select count(*) from public.admin_list_accounts(100, 0)) >= 2, 'the wrapped list still returns accounts');
select lives_ok($$ select * from public.admin_support_requests('open', 50) $$, 'the support queue still reads');
select lives_ok($$ select * from public.admin_reported_accounts(10) $$, 'and the reported accounts');
select lives_ok($$ select * from public.admin_most_blocked(2, 10) $$, 'and the most blocked');
select lives_ok($$ select * from public.admin_lookup_account('member@audit.test') $$, 'and the search box');
select is((select count(*) from public.admin_open_attachment(gen_random_uuid(), gen_random_uuid())), 0::bigint,
  'an attachment that is not there opens nothing');

reset role;
select is(pg_temp.reads('read.accounts'), 1::bigint, 'reading the account list is logged');
select ok((select (details ->> 'rows')::int >= 2 from private.admin_audit_log
           where action = 'read.accounts' and actor_id = 'b8b8b8b8-0000-4000-8000-000000000001'),
  'with how many rows came back');
select is(pg_temp.reads('read.support_queue'), 1::bigint, 'so is the support queue');
select is(pg_temp.reads('read.lookup'), 0::bigint, 'the search box is not logged per keystroke');
select is(pg_temp.reads('read.attachment'), 0::bigint, 'nor is an attachment that was not found');

-- Somebody without the role is refused before anything is counted or logged.
set local role authenticated;
select pg_temp.as_member();
select throws_ok($$ select * from public.admin_list_accounts(100, 0) $$, '42501', null,
  'a member cannot read the account list');
select throws_ok($$ select * from public.admin_audit_recent() $$, '42501', null, 'nor the log');

-- The log by actor.
select pg_temp.as_admin();
select ok((select bool_and(r.actor_id = 'b8b8b8b8-0000-4000-8000-000000000001')
           from public.admin_audit_recent('b8b8b8b8-0000-4000-8000-000000000001', 50) r),
  'the log reads by actor');

select throws_ok(
  $$ do $x$ begin for i in 1..400 loop perform * from public.admin_lookup_account('nobody'); end loop; end $x$ $$,
  'P0001', 'admin_read_limit', 'reads stop at 300 an hour');
reset role;

-- Append-only, even for the owner.
select throws_ok($$ update private.admin_audit_log set action = 'tidied' $$, '42501', null, 'the log cannot be edited');
select throws_ok($$ delete from private.admin_audit_log $$, '42501', null, 'or deleted from');

select * from finish();
rollback;
