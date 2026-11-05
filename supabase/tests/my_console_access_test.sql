-- What the console door is told, in stage 1 of admin MFA (20261124000000). Written to hold after
-- stage 2 as well, apart from `data_gate_open` at aal1, which is asserted only for an aal2 session
-- here and for aal1 in admin_mfa_enforcement_test.sql once that exists.

begin;
select plan(13);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('cccccccc-8888-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin@consoleaccess.test', 'x', now(), now(), now()),
  ('cccccccc-8888-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'nobody@consoleaccess.test', 'x', now(), now(), now());

insert into public.feedback_admins (profile_id, role) values
  ('cccccccc-8888-0000-0000-000000000001', 'billing');

select set_config('request.jwt.claims',
  '{"sub":"cccccccc-8888-0000-0000-000000000001","role":"authenticated","aal":"aal1"}', true);
set local role authenticated;

select is(public.my_console_access() ->> 'is_admin', 'true', 'an admin is on the roster at aal1');
select is(public.my_console_access() ->> 'aal', 'aal1', 'the level comes from the JWT');
select is(public.my_console_access() ->> 'has_verified_factor', 'false', 'no factor yet');
select is(public.my_admin_roles() ->> 'member', 'true', 'the door to the console stays visible');

reset role;

-- An unverified factor is an enrolment nobody finished, and does not count.
insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
values (gen_random_uuid(), 'cccccccc-8888-0000-0000-000000000001', 'Started', 'totp', 'unverified', now(), now());
set local role authenticated;
select is(public.my_console_access() ->> 'has_verified_factor', 'false', 'an unverified factor does not count');
reset role;

insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
values (gen_random_uuid(), 'cccccccc-8888-0000-0000-000000000001', 'Finished', 'totp', 'verified', now(), now());

select set_config('request.jwt.claims',
  '{"sub":"cccccccc-8888-0000-0000-000000000001","role":"authenticated","aal":"aal2"}', true);
set local role authenticated;

select is(public.my_console_access() ->> 'aal', 'aal2', 'aal2 is reported');
select is(public.my_console_access() ->> 'has_verified_factor', 'true', 'a verified factor counts');
select is(public.my_console_access() ->> 'data_gate_open', 'true', 'the gate is open at aal2');

-- Somebody else's factor and roster row say nothing about this caller.
select set_config('request.jwt.claims',
  '{"sub":"cccccccc-8888-0000-0000-000000000002","role":"authenticated","aal":"aal2"}', true);

select is(public.my_console_access() ->> 'is_admin', 'false', 'a stranger is not on the roster');
select is(public.my_console_access() ->> 'has_verified_factor', 'false', 'and has no factor');
select is(public.my_admin_roles() ->> 'member', 'false', 'and sees no door');

reset role;

select ok(not has_function_privilege('anon', 'public.my_console_access()', 'EXECUTE'),
  'anon cannot ask');
select ok(has_function_privilege('authenticated', 'public.my_console_access()', 'EXECUTE'),
  'a signed-in user can');

select * from finish();
rollback;
