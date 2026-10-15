-- The audit log cannot be written by somebody who is not an admin.
--
-- `admin_record_action` takes its actor as an argument, which is only safe while the service role
-- alone can call it. 20261110000600's catalogue loop re-granted it to `authenticated` on the
-- assumption that every `admin_%` function checks a role inside; this one is a bare INSERT. So
-- these assert both the specific grant and the assumption itself, over the catalogue, so a future
-- function with the same shape is caught the day it is added.

begin;
select plan(6);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('c0a5c0a5-a0d1-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin@forgery.test', 'x', now(), now(), now()),
  ('c0a5c0a5-a0d1-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'nobody@forgery.test', 'x', now(), now(), now());

insert into public.profiles (id, first_name) values
  ('c0a5c0a5-a0d1-4000-8000-000000000001', 'Sam'),
  ('c0a5c0a5-a0d1-4000-8000-000000000002', 'Rae')
on conflict (id) do update set first_name = excluded.first_name;

insert into public.feedback_admins (profile_id, role)
values ('c0a5c0a5-a0d1-4000-8000-000000000001', 'support');

select ok(
  not has_function_privilege('authenticated', 'public.admin_record_action(uuid, text, uuid, text, jsonb)', 'EXECUTE'),
  'a signed-in user cannot execute admin_record_action'
);
select ok(
  has_function_privilege('service_role', 'public.admin_record_action(uuid, text, uuid, text, jsonb)', 'EXECUTE'),
  'admin-actions, acting as the service role, still can'
);

-- The exploit itself: a non-admin writing a deletion into the log under the real admin's name.
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"c0a5c0a5-a0d1-4000-8000-000000000002","role":"authenticated"}', true);

select throws_ok(
  $$ select public.admin_record_action(
       'c0a5c0a5-a0d1-4000-8000-000000000001', 'account.delete',
       'c0a5c0a5-a0d1-4000-8000-000000000002', 'forged', '{}') $$,
  '42501',
  null,
  'a non-admin calling it is refused'
);

reset role;

select is(
  (select count(*)::int from private.admin_audit_log where reason = 'forged'),
  0,
  'and nothing reached the log'
);

-- Not a regression of the legitimate path: an admin's own RPCs still record through the private
-- helper, which reads the actor from the session rather than taking it.
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"c0a5c0a5-a0d1-4000-8000-000000000001","role":"authenticated"}', true);
select lives_ok(
  $$ select public.admin_grant_streak_repair('c0a5c0a5-a0d1-4000-8000-000000000002', 'apology for the outage') $$,
  'a support admin''s own action still records'
);
reset role;

-- The rule 20261110000600 assumed and did not check. Every function in the admin family that a
-- signed-in user can execute must test a role itself, because `authenticated` is everybody.
select is(
  (select coalesce(string_agg(p.proname, ', ' order by p.proname), '')
   from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and (p.proname like 'admin\_%' or p.proname like 'api\_usage\_%'
          or p.proname in ('reserve_support_attachment', 'support_attachments_for_send', 'support_thread_for_reply'))
     and has_function_privilege('authenticated', p.oid, 'EXECUTE')
     and p.prosrc !~ 'is_(support|billing|feedback|console)_admin\('),
  '',
  'every admin function a signed-in user can execute checks a role inside'
);

select * from finish();
rollback;
