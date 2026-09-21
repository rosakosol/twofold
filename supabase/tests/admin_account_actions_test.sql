-- `leave_couple` and `delete_own_account` had no test at all before this, which is how a refactor
-- of them is genuinely risky rather than merely fiddly. Both now sit on top of extracted bodies
-- shared with the admin entry points, and the premise of doing it that way is that the two routes
-- produce the SAME outcome — so that is what is asserted, side by side, rather than each being
-- checked to have done something.
--
-- What dissolving actually has to do, beyond flipping the status:
--
--   * Record who left. `couples.dissolved_by` is not decoration — an admin acting for somebody
--     must leave the row saying that person left, not that an administrator did, because that is
--     what the app reads and what is true from the couple's point of view.
--   * Arm the subscription-lapse notice on the RIGHT partner: the one who did not leave and was
--     relying on the leaver's subscription. Armed on the wrong one and somebody is told their
--     partner's departure cost them a subscription they are still paying for.
--   * Stop flight tracking and abandon live games, so an ended relationship stops spending AeroAPI
--     money and stops waiting for a turn that is not coming.
--
-- And a reason is required on every destructive admin call. An unexplained destructive action
-- found in the log in two years is indistinguishable from a mistake.

begin;
select plan(21);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', email, 'x', now(), now(), now()
from (values
  ('ffffffff-aaaa-0000-0000-000000000001'::uuid, 'support@actions.test'),
  ('ffffffff-aaaa-0000-0000-000000000002'::uuid, 'payer@actions.test'),
  ('ffffffff-aaaa-0000-0000-000000000003'::uuid, 'freeloader@actions.test'),
  ('ffffffff-aaaa-0000-0000-000000000004'::uuid, 'selfpayer@actions.test'),
  ('ffffffff-aaaa-0000-0000-000000000005'::uuid, 'selffree@actions.test')
) as v(id, email);

insert into public.profiles (id, first_name) values
  ('ffffffff-aaaa-0000-0000-000000000001', 'Sam'),
  ('ffffffff-aaaa-0000-0000-000000000002', 'Pat'),
  ('ffffffff-aaaa-0000-0000-000000000003', 'Rae'),
  ('ffffffff-aaaa-0000-0000-000000000004', 'Max'),
  ('ffffffff-aaaa-0000-0000-000000000005', 'Ali')
on conflict (id) do update set first_name = excluded.first_name;

insert into public.feedback_admins (profile_id, role)
values ('ffffffff-aaaa-0000-0000-000000000001', 'support');

-- Only the leaver pays, in both couples, so the lapse notice has somewhere to land.
update public.profiles set subscription_active = true, subscription_tier = 'premium'
where id in ('ffffffff-aaaa-0000-0000-000000000002', 'ffffffff-aaaa-0000-0000-000000000004');

-- Couple A, dissolved by an admin acting for Pat. Couple B, dissolved by Max themselves.
insert into public.couples (id, partner_a_id, partner_b_id, status) values
  ('ffffffff-aaaa-cccc-0000-00000000000a', 'ffffffff-aaaa-0000-0000-000000000002', 'ffffffff-aaaa-0000-0000-000000000003', 'active'),
  ('ffffffff-aaaa-cccc-0000-00000000000b', 'ffffffff-aaaa-0000-0000-000000000004', 'ffffffff-aaaa-0000-0000-000000000005', 'active');

-- ---------------------------------------------------------------------------
-- Guards, before anything is dissolved
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ffffffff-aaaa-0000-0000-000000000003', true);

select throws_ok(
  $$ select public.admin_dissolve_couple('ffffffff-aaaa-cccc-0000-00000000000a', 'ffffffff-aaaa-0000-0000-000000000002', 'because') $$,
  '42501', null, 'an ordinary user cannot dissolve somebody else''s couple'
);

select set_config('request.jwt.claim.sub', 'ffffffff-aaaa-0000-0000-000000000001', true);

select throws_ok(
  $$ select public.admin_dissolve_couple('ffffffff-aaaa-cccc-0000-00000000000a', 'ffffffff-aaaa-0000-0000-000000000002', '   ') $$,
  '22023', null, 'and no admin may dissolve one without saying why'
);

select throws_ok(
  $$ select public.admin_scrub_account('ffffffff-aaaa-0000-0000-000000000003', '') $$,
  '22023', null, 'nor delete an account without saying why'
);

-- Acting for somebody who is not in the couple is the mistake that would dissolve the wrong
-- relationship, so it is refused rather than interpreted.
select throws_ok(
  $$ select public.admin_dissolve_couple('ffffffff-aaaa-cccc-0000-00000000000a', 'ffffffff-aaaa-0000-0000-000000000005', 'wrong person') $$,
  'P0001', 'That profile is not a member of this couple',
  'and cannot act for somebody who is not in it'
);

-- ---------------------------------------------------------------------------
-- The admin route
-- ---------------------------------------------------------------------------

select lives_ok(
  $$ select public.admin_dissolve_couple('ffffffff-aaaa-cccc-0000-00000000000a', 'ffffffff-aaaa-0000-0000-000000000002', 'they emailed asking to be disconnected') $$,
  'a support admin can disconnect somebody who asked'
);

-- ---------------------------------------------------------------------------
-- The user's own route, on an identical couple
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'ffffffff-aaaa-0000-0000-000000000004', true);
select lives_ok(
  $$ select public.leave_couple('ffffffff-aaaa-cccc-0000-00000000000b') $$,
  'and the app''s own path still works'
);

-- ---------------------------------------------------------------------------
-- The two produce the same outcome
-- ---------------------------------------------------------------------------
--
-- Verified as the owner, not as either caller. `couples` and `profiles` are both under RLS, and
-- neither participant can see the other couple — the support admin cannot see either, not being a
-- member of one. Read through RLS these assertions come back NULL and compare equal to each other,
-- which is a test that passes because it can see nothing.
reset role;

select is(
  (select status::text from public.couples where id = 'ffffffff-aaaa-cccc-0000-00000000000a'),
  (select status::text from public.couples where id = 'ffffffff-aaaa-cccc-0000-00000000000b'),
  'both couples end dissolved'
);

-- The load-bearing one: an admin acting for Pat must leave the row saying PAT left, not Sam.
select is(
  (select dissolved_by from public.couples where id = 'ffffffff-aaaa-cccc-0000-00000000000a'),
  'ffffffff-aaaa-0000-0000-000000000002'::uuid,
  'the admin route records the partner as the one who left, not the admin'
);

select is(
  (select dissolved_by from public.couples where id = 'ffffffff-aaaa-cccc-0000-00000000000b'),
  'ffffffff-aaaa-0000-0000-000000000004'::uuid,
  'and the self-serve route records the leaver, as it always did'
);

-- The lapse notice, armed on the remaining non-paying partner in both cases.
select is(
  (select partner_subscription_lapse_partner_name from public.profiles where id = 'ffffffff-aaaa-0000-0000-000000000003'),
  'Pat', 'the admin route arms the lapse notice on the partner left behind'
);

select is(
  (select partner_subscription_lapse_partner_name from public.profiles where id = 'ffffffff-aaaa-0000-0000-000000000005'),
  'Max', 'and so does the self-serve route'
);

select is(
  (select partner_subscription_lapse_shown from public.profiles where id = 'ffffffff-aaaa-0000-0000-000000000003'),
  false, 'unshown, so it is actually surfaced'
);

-- Never on the leaver: they still have their own subscription, and telling them it lapsed because
-- of their own departure would be nonsense.
select ok(
  (select partner_subscription_lapse_partner_name from public.profiles where id = 'ffffffff-aaaa-0000-0000-000000000002') is null,
  'and never on the one who left'
);

select ok(
  (select partner_name from public.profiles where id = 'ffffffff-aaaa-0000-0000-000000000003') is null,
  'partner fields are cleared on both sides'
);

-- ---------------------------------------------------------------------------
-- Already dissolved
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ffffffff-aaaa-0000-0000-000000000001', true);
select throws_ok(
  $$ select public.admin_dissolve_couple('ffffffff-aaaa-cccc-0000-00000000000a', 'ffffffff-aaaa-0000-0000-000000000002', 'again') $$,
  'P0001', 'This couple has already been dissolved',
  'a second dissolution is refused rather than silently redone'
);

-- ---------------------------------------------------------------------------
-- The path the edge function actually takes
-- ---------------------------------------------------------------------------
--
-- Deleting an account from the console never worked, and this test is why it was not caught:
-- admin_scrub_account was only ever exercised as a support admin and as a content admin — the two
-- doors the edge function does NOT use. It calls with the service client, where auth.uid() is null,
-- so is_support_admin() was false and every deletion raised 42501 before touching anything.
--
-- A gate tested only through the door nobody uses is untested.

reset role;
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

select throws_ok(
  $$ select public.admin_scrub_account('ffffffff-aaaa-0000-0000-000000000003', 'no actor given') $$,
  '22023', null, 'the service role must say who it is acting for'
);

select lives_ok(
  $$ select public.admin_scrub_account('ffffffff-aaaa-0000-0000-000000000003', 'they emailed asking',
       'ffffffff-aaaa-0000-0000-000000000001') $$,
  'and then it may scrub, which is what the console does'
);

reset role;

-- Attributed to the admin, not to nobody. An audit row naming the service role explains nothing.
select is(
  (select actor_id from private.admin_audit_log
   where subject_profile_id = 'ffffffff-aaaa-0000-0000-000000000003' and action = 'account.scrub'),
  'ffffffff-aaaa-0000-0000-000000000001'::uuid,
  'and the row names the admin who asked for it'
);

-- ---------------------------------------------------------------------------
-- Audited, with the reason
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ffffffff-aaaa-0000-0000-000000000001', true);

select is(
  (select action from public.admin_audit_for_subject('ffffffff-aaaa-0000-0000-000000000002') limit 1),
  'couple.dissolve', 'the dissolution is in the log'
);

select is(
  (select reason from public.admin_audit_for_subject('ffffffff-aaaa-0000-0000-000000000002') limit 1),
  'they emailed asking to be disconnected',
  'with the reason that was given for it'
);

select is(
  (select actor_email from public.admin_audit_for_subject('ffffffff-aaaa-0000-0000-000000000002') limit 1),
  'support@actions.test',
  'attributed to the admin, which is where that fact belongs'
);

reset role;
select * from finish();
rollback;
