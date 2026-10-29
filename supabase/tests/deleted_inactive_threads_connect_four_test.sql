-- 20261114005000: deleted accounts are inactive at once, deleted admins lose the role, support
-- threads join only genuine conversations, and Connect 4 needs Premium to keep playing.

begin;
select plan(16);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', email, 'x', now(), now(), now()
from (values
  ('d1d1d1d1-0000-4000-8000-000000000001'::uuid, 'gone@decisions.test'),
  ('d1d1d1d1-0000-4000-8000-000000000002'::uuid, 'here@decisions.test'),
  ('d1d1d1d1-0000-4000-8000-000000000003'::uuid, 'admin@decisions.test'),
  ('d1d1d1d1-0000-4000-8000-000000000004'::uuid, 'lapsed-a@decisions.test'),
  ('d1d1d1d1-0000-4000-8000-000000000005'::uuid, 'lapsed-b@decisions.test'),
  ('d1d1d1d1-0000-4000-8000-000000000006'::uuid, 'prem-a@decisions.test'),
  ('d1d1d1d1-0000-4000-8000-000000000007'::uuid, 'prem-b@decisions.test')
) as v(id, email);

insert into public.profiles (id, first_name) values
  ('d1d1d1d1-0000-4000-8000-000000000001', 'Gone'),
  ('d1d1d1d1-0000-4000-8000-000000000002', 'Here'),
  ('d1d1d1d1-0000-4000-8000-000000000003', 'Adm'),
  ('d1d1d1d1-0000-4000-8000-000000000004', 'La'),
  ('d1d1d1d1-0000-4000-8000-000000000005', 'Lb'),
  ('d1d1d1d1-0000-4000-8000-000000000006', 'Pa'),
  ('d1d1d1d1-0000-4000-8000-000000000007', 'Pb')
on conflict (id) do update set first_name = excluded.first_name;

update public.profiles set account_deleted_at = now() where id = 'd1d1d1d1-0000-4000-8000-000000000001';
update public.profiles set subscription_active = true, subscription_tier = 'premium'
  where id = 'd1d1d1d1-0000-4000-8000-000000000006';
insert into public.feedback_admins (profile_id, role) values ('d1d1d1d1-0000-4000-8000-000000000003', 'support');

-- ---------------------------------------------------------------------------
-- 1. Deleted accounts
-- ---------------------------------------------------------------------------

select ok(
  (select rolconfig::text from pg_roles where rolname = 'authenticator') like '%pgrst.db_pre_request=public.reject_deleted_accounts%',
  'every API request runs the deleted-account check first'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1d1d1d1-0000-4000-8000-000000000001', true);
select throws_ok($$ select public.reject_deleted_accounts() $$, '42501', 'account_deleted',
  'a deleted account is refused');
select is(public.can_access_storage_object('avatar', 'd1d1d1d1-0000-4000-8000-000000000001/avatar.jpg', 'read'), false,
  'and cannot reach even its own files');

select set_config('request.jwt.claim.sub', 'd1d1d1d1-0000-4000-8000-000000000002', true);
select lives_ok($$ select public.reject_deleted_accounts() $$, 'a live account is not');
select is(public.can_access_storage_object('avatar', 'd1d1d1d1-0000-4000-8000-000000000002/avatar.jpg', 'read'), true,
  'and keeps its own files');
reset role;

-- ---------------------------------------------------------------------------
-- 2. Admin role
-- ---------------------------------------------------------------------------

select private.scrub_account('d1d1d1d1-0000-4000-8000-000000000003');
select is((select count(*)::int from public.feedback_admins where profile_id = 'd1d1d1d1-0000-4000-8000-000000000003'), 0,
  'deleting an admin removes the role');

-- ---------------------------------------------------------------------------
-- 3. Support threads
-- ---------------------------------------------------------------------------

-- An existing thread, from real mail sent by here@ under a subject.
create temporary table t (label text, id uuid) on commit drop;
grant all on t to anon, authenticated, service_role;
insert into t select 'mail', public.ingest_support_email('decisions-1@mail', 'here@decisions.test', 'Here', 'Billing question', 'first', now(), null);
insert into t select 'mail again', public.ingest_support_email('decisions-2@mail', 'here@decisions.test', 'Here', 'Re: Billing question', 'second', now(), null);

set local role service_role;
select set_config('request.jwt.claim.sub', '', true);
insert into t select 'web', public.submit_support_request(
  p_category => 'Other', p_message => 'stranger', p_subject => 'Billing question',
  p_email => 'here@decisions.test', p_source => 'web');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1d1d1d1-0000-4000-8000-000000000002', true);
insert into t select 'app 1', public.submit_support_request(p_category => 'Bug Report', p_message => 'crash', p_source => 'app');
insert into t select 'app 2', public.submit_support_request(p_category => 'Feedback', p_message => 'idea', p_source => 'app');
reset role;

select is(
  (select thread_id from public.support_requests where id = (select id from t where label = 'mail again')),
  (select thread_id from public.support_requests where id = (select id from t where label = 'mail')),
  'mail from the same address with the same subject joins its thread'
);
select isnt(
  (select thread_id from public.support_requests where id = (select id from t where label = 'web')),
  (select thread_id from public.support_requests where id = (select id from t where label = 'mail')),
  'a website-form message typed with that address and subject does not'
);
select isnt(
  (select thread_id from public.support_requests where id = (select id from t where label = 'app 1')),
  (select thread_id from public.support_requests where id = (select id from t where label = 'app 2')),
  'two app messages with no subject are two conversations, not one'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1d1d1d1-0000-4000-8000-000000000003', true);
-- The admin was scrubbed above; give the role back for the listing checks.
reset role;
insert into public.feedback_admins (profile_id, role) values ('d1d1d1d1-0000-4000-8000-000000000003', 'support');
update public.profiles set account_deleted_at = null where id = 'd1d1d1d1-0000-4000-8000-000000000003';
set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1d1d1d1-0000-4000-8000-000000000003', true);
select is(
  (select matched_profile_id from public.admin_support_requests(null, 200) where id = (select id from t where label = 'web')),
  null,
  'a website-form thread is not linked to the account its typed address belongs to'
);
select is(
  (select matched_profile_id from public.admin_support_requests(null, 200) where id = (select id from t where label = 'mail')),
  'd1d1d1d1-0000-4000-8000-000000000002'::uuid,
  'mail actually sent from the address still is'
);
reset role;

-- ---------------------------------------------------------------------------
-- 4. Connect 4
-- ---------------------------------------------------------------------------

insert into public.couples (id, partner_a_id, partner_b_id, status) values
  ('d1d1d1d1-0000-4000-8000-0000000000c1', 'd1d1d1d1-0000-4000-8000-000000000004', 'd1d1d1d1-0000-4000-8000-000000000005', 'active'),
  ('d1d1d1d1-0000-4000-8000-0000000000c2', 'd1d1d1d1-0000-4000-8000-000000000006', 'd1d1d1d1-0000-4000-8000-000000000007', 'active');
insert into public.game_sessions (id, couple_id, game_type, initiator_id, status, total_rounds) values
  ('d1d1d1d1-0000-4000-8000-0000000000a1', 'd1d1d1d1-0000-4000-8000-0000000000c1', 'connect_four', 'd1d1d1d1-0000-4000-8000-000000000004', 'active', 1),
  ('d1d1d1d1-0000-4000-8000-0000000000a2', 'd1d1d1d1-0000-4000-8000-0000000000c2', 'connect_four', 'd1d1d1d1-0000-4000-8000-000000000006', 'active', 1);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1d1d1d1-0000-4000-8000-000000000004', true);
select throws_ok($$ select * from public.play_connect_four_move('d1d1d1d1-0000-4000-8000-0000000000a1', 3) $$,
  'P0001', 'connect_four_requires_premium', 'a couple without Premium cannot keep playing');

select set_config('request.jwt.claim.sub', 'd1d1d1d1-0000-4000-8000-000000000006', true);
select lives_ok($$ select * from public.play_connect_four_move('d1d1d1d1-0000-4000-8000-0000000000a2', 3) $$,
  'a Premium couple can');
reset role;
select is((select count(*)::int from public.game_moves where session_id = 'd1d1d1d1-0000-4000-8000-0000000000a1'), 0,
  'the lapsed board is untouched');
select is((select count(*)::int from public.game_moves where session_id = 'd1d1d1d1-0000-4000-8000-0000000000a2'), 1,
  'and the Premium move landed');
select is((select status from public.game_sessions where id = 'd1d1d1d1-0000-4000-8000-0000000000a1'), 'active',
  'the paused game is kept, not ended');

select * from finish();
rollback;
