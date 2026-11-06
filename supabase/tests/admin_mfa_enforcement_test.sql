-- Stage 2 of admin MFA: an admin's powers need aal2, and nothing else changes. Lives in
-- supabase/pending/ with its migration, because `supabase test db` would fail on it until then.
-- Moves to supabase/tests/ at the same time (see supabase/pending/README.md).

begin;
select plan(35);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('cccccccc-9999-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'all@mfaenforce.test', 'x', now(), now(), now()),
  ('cccccccc-9999-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'nobody@mfaenforce.test', 'x', now(), now(), now());

insert into public.feedback_admins (profile_id, role) values
  ('cccccccc-9999-0000-0000-000000000001', 'content'),
  ('cccccccc-9999-0000-0000-000000000001', 'support'),
  ('cccccccc-9999-0000-0000-000000000001', 'billing');

-- ---------------------------------------------------------------------------
-- A user's JWT at aal1: the case all of this exists for
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims',
  '{"sub":"cccccccc-9999-0000-0000-000000000001","role":"authenticated","aal":"aal1"}', true);
set local role authenticated;

select ok(not public.is_feedback_admin(), 'aal1: no content');
select ok(not public.is_support_admin(), 'aal1: no support');
select ok(not public.is_billing_admin(), 'aal1: no billing');
select ok(not public.is_console_admin(), 'aal1: no console');
select ok(not public.is_support_admin('cccccccc-9999-0000-0000-000000000001'),
  'aal1: naming your own id does not get round it');
select throws_ok($$ select public.admin_list_accounts(10, 0) $$, '42501', null,
  'aal1: an admin function refuses');
select is(public.my_admin_roles() ->> 'support', 'false', 'aal1: no role is reported');

-- The console's routing still sees the person, and that the door is shut.
select is(public.my_console_access() ->> 'is_admin', 'true', 'aal1: still on the roster');
select is(public.my_console_access() ->> 'data_gate_open', 'false', 'aal1: the gate says so');
select is(public.my_admin_roles() ->> 'member', 'true', 'aal1: the door stays visible');

-- ---------------------------------------------------------------------------
-- A missing `aal` is not a pass
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims',
  '{"sub":"cccccccc-9999-0000-0000-000000000001","role":"authenticated"}', true);
select ok(not public.is_support_admin(), 'no aal claim: no support');
select ok(not public.is_console_admin(), 'no aal claim: no console');

-- ---------------------------------------------------------------------------
-- The same person at aal2
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims',
  '{"sub":"cccccccc-9999-0000-0000-000000000001","role":"authenticated","aal":"aal2"}', true);

select ok(public.is_feedback_admin(), 'aal2: content');
select ok(public.is_support_admin(), 'aal2: support');
select ok(public.is_billing_admin(), 'aal2: billing');
select ok(public.is_console_admin(), 'aal2: console');
select is(public.my_console_access() ->> 'data_gate_open', 'true', 'aal2: the gate is open');
select lives_ok($$ select public.admin_list_accounts(10, 0) $$, 'aal2: an admin function runs');

-- aal2 proves a second factor, not a role.
select set_config('request.jwt.claims',
  '{"sub":"cccccccc-9999-0000-0000-000000000002","role":"authenticated","aal":"aal2"}', true);
select ok(not public.is_support_admin(), 'aal2 without a role: no support');
select ok(not public.is_console_admin(), 'aal2 without a role: no console');

-- ---------------------------------------------------------------------------
-- Everything that is not a user's JWT behaves as it always did
-- ---------------------------------------------------------------------------
reset role;

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select ok(public.is_support_admin('cccccccc-9999-0000-0000-000000000001'),
  'service role: an explicit id answers from the roster');
select ok(public.is_console_admin('cccccccc-9999-0000-0000-000000000001'), 'service role: console too');
select ok(not public.is_support_admin(), 'service role: the default argument is null and finds nothing');

select set_config('request.jwt.claims', '{"role":"anon"}', true);
select ok(not public.is_support_admin(), 'anon: no');
select ok(not public.is_feedback_admin(), 'anon: no');
select ok(not has_function_privilege('anon', 'public.is_support_admin(uuid)', 'EXECUTE'),
  'anon still cannot call it directly');

select set_config('request.jwt.claims', '', true);
select ok(public.is_support_admin('cccccccc-9999-0000-0000-000000000001'),
  'no JWT (cron, SQL Editor): an explicit id answers from the roster');
select ok(public.is_feedback_admin('cccccccc-9999-0000-0000-000000000001'), 'no JWT: content');
select ok(public.is_billing_admin('cccccccc-9999-0000-0000-000000000001'), 'no JWT: billing');
select ok(public.is_console_admin('cccccccc-9999-0000-0000-000000000001'), 'no JWT: console');
select ok(not public.is_support_admin(), 'no JWT: the default argument finds nothing');

-- ---------------------------------------------------------------------------
-- Same shape as before, and the helper is out of reach
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('is_feedback_admin', 'is_support_admin', 'is_billing_admin', 'is_console_admin')
     and p.prosecdef
     and p.provolatile = 's'
     and p.proconfig = array['search_path=public']
     and pg_get_function_identity_arguments(p.oid) = 'check_id uuid'),
  4,
  'all four keep their signature, security definer, stability and search_path'
);
select ok(has_function_privilege('authenticated', 'public.is_support_admin(uuid)', 'EXECUTE'),
  'authenticated keeps EXECUTE, which the RLS policies need');
select ok(not has_function_privilege('authenticated', 'private.admin_session_has_mfa()', 'EXECUTE'),
  'clients cannot call the helper');
select ok(not has_schema_privilege('authenticated', 'private', 'USAGE'),
  'nor reach its schema');

select * from finish();
rollback;
