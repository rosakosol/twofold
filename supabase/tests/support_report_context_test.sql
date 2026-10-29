-- An abuse report names who it is about, in the row the console reads, and only when a signed-in
-- reporter files one. The console's view of that person is for support admins only. Saved replies
-- are support admins' alone.

begin;
select plan(14);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', email, 'x', now(), now(), now()
from (values
  ('cccccccc-eeee-0000-0000-000000000001'::uuid, 'reporter@report.test'),
  ('cccccccc-eeee-0000-0000-000000000002'::uuid, 'reported@report.test'),
  ('cccccccc-eeee-0000-0000-000000000003'::uuid, 'support@report.test')
) as v(id, email);

insert into public.profiles (id, first_name) values
  ('cccccccc-eeee-0000-0000-000000000001', 'Rita'),
  ('cccccccc-eeee-0000-0000-000000000002', 'Rex'),
  ('cccccccc-eeee-0000-0000-000000000003', 'Sue')
on conflict (id) do update set first_name = excluded.first_name;

insert into public.feedback_admins (profile_id, role) values ('cccccccc-eeee-0000-0000-000000000003', 'support');
insert into public.couples (partner_a_id, partner_b_id, status) values
  ('cccccccc-eeee-0000-0000-000000000001', 'cccccccc-eeee-0000-0000-000000000002', 'active');
insert into public.blocked_profiles (blocker_id, blocked_id) values
  ('cccccccc-eeee-0000-0000-000000000001', 'cccccccc-eeee-0000-0000-000000000002');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'cccccccc-eeee-0000-0000-000000000001', true);

-- ---------------------------------------------------------------------------
-- Filing
-- ---------------------------------------------------------------------------

create temporary table filed (label text, id uuid) on commit drop;
grant all on filed to authenticated;

insert into filed select 'report', public.submit_support_request(
  p_category => 'Report Abuse', p_message => 'He keeps messaging me', p_source => 'app',
  p_reported_profile_id => 'cccccccc-eeee-0000-0000-000000000002', p_report_surface => 'partner settings');
insert into filed select 'not a report', public.submit_support_request(
  p_category => 'Bug Report', p_message => 'Crash', p_source => 'app',
  p_reported_profile_id => 'cccccccc-eeee-0000-0000-000000000002');
insert into filed select 'self', public.submit_support_request(
  p_category => 'Report Abuse', p_message => 'Me', p_source => 'app',
  p_reported_profile_id => 'cccccccc-eeee-0000-0000-000000000001');
-- The six-argument call every existing caller makes still resolves.
insert into filed select 'old shape', public.submit_support_request(
  p_category => 'Feedback', p_message => 'Love it', p_subject => null, p_source => 'app');

reset role;

select is((select reported_profile_id from public.support_requests where id = (select id from filed where label = 'report')),
  'cccccccc-eeee-0000-0000-000000000002'::uuid, 'a report records who it is about');
select is((select report_surface from public.support_requests where id = (select id from filed where label = 'report')),
  'partner settings', 'and where the reporter reached them');
select is((select reported_profile_id from public.support_requests where id = (select id from filed where label = 'not a report')),
  null, 'another category cannot name anybody');
select is((select reported_profile_id from public.support_requests where id = (select id from filed where label = 'self')),
  null, 'nor can a report about yourself');
select isnt((select id from filed where label = 'old shape'), null, 'existing callers are unaffected');

-- Anonymous: the website form, which calls it as the service role. It cannot name an account.
set local role service_role;
select set_config('request.jwt.claim.sub', '', true);
select lives_ok($$ select public.submit_support_request(
  p_category => 'Report Abuse', p_message => 'Anon report', p_email => 'x@y.test', p_source => 'web',
  p_reported_profile_id => 'cccccccc-eeee-0000-0000-000000000002') $$, 'a website submission still files');
reset role;
select is((select reported_profile_id from public.support_requests where message = 'Anon report'),
  null, 'but cannot attach anybody to it');

-- ---------------------------------------------------------------------------
-- What the console sees
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'cccccccc-eeee-0000-0000-000000000001', true);
select throws_ok(format('select * from public.admin_report_context(%L)', (select id from filed where label = 'report')),
  '42501', null, 'a user cannot look up who was reported');

select set_config('request.jwt.claim.sub', 'cccccccc-eeee-0000-0000-000000000003', true);
select results_eq(
  format($$ select first_name, email, times_reported, distinct_reporters, reporter_blocked_them, are_partners
            from public.admin_report_context(%L) $$, (select id from filed where label = 'report')),
  $$ values ('Rex'::text, 'reported@report.test'::text, 1, 1, true, true) $$,
  'support sees who it is, how often they have been reported, the block and the relationship');
select is((select count(*)::int from public.admin_report_context((select id from filed where label = 'not a report'))), 0,
  'a request naming nobody has no report context');
select is((select reported_name from public.admin_support_requests(null, 200) where id = (select id from filed where label = 'report')),
  'Rex', 'and the inbox list names who the report is about');

reset role;
select is((select count(*)::int from private.admin_audit_log where action = 'report.view'
  and subject_profile_id = 'cccccccc-eeee-0000-0000-000000000002'), 1, 'and looking is recorded');

-- ---------------------------------------------------------------------------
-- Saved replies
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'cccccccc-eeee-0000-0000-000000000001', true);
select is((select count(*)::int from public.support_macros), 0, 'a user cannot read saved replies');

select set_config('request.jwt.claim.sub', 'cccccccc-eeee-0000-0000-000000000003', true);
select lives_ok($$ insert into public.support_macros (title, body) values ('Test reply', 'Hi {{name}}') $$,
  'support can save one');

select * from finish();
rollback;
