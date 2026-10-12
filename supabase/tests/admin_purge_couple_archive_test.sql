-- Purging an archive early is allowed only when both partners have deleted their accounts. That
-- condition is the whole justification for skipping the 90-day timer, so it is checked here the way
-- a hand-built call would hit it, not just through the console that hides the button.

begin;
select plan(11);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', email, 'x', now(), now(), now()
from (values
  ('eeeeeeee-bbbb-0000-0000-000000000001'::uuid, 'support@purge.test'),
  ('eeeeeeee-bbbb-0000-0000-000000000002'::uuid, 'gone-a@purge.test'),
  ('eeeeeeee-bbbb-0000-0000-000000000003'::uuid, 'gone-b@purge.test'),
  ('eeeeeeee-bbbb-0000-0000-000000000004'::uuid, 'stayed@purge.test'),
  ('eeeeeeee-bbbb-0000-0000-000000000005'::uuid, 'left@purge.test'),
  ('eeeeeeee-bbbb-0000-0000-000000000006'::uuid, 'active-a@purge.test'),
  ('eeeeeeee-bbbb-0000-0000-000000000007'::uuid, 'active-b@purge.test')
) as v(id, email);

insert into public.profiles (id, first_name) values
  ('eeeeeeee-bbbb-0000-0000-000000000001', 'Sam'),
  ('eeeeeeee-bbbb-0000-0000-000000000002', 'Deleted User'),
  ('eeeeeeee-bbbb-0000-0000-000000000003', 'Deleted User'),
  ('eeeeeeee-bbbb-0000-0000-000000000004', 'Jo'),
  ('eeeeeeee-bbbb-0000-0000-000000000005', 'Deleted User'),
  ('eeeeeeee-bbbb-0000-0000-000000000006', 'Deleted User'),
  ('eeeeeeee-bbbb-0000-0000-000000000007', 'Deleted User')
on conflict (id) do update set first_name = excluded.first_name;

update public.profiles set account_deleted_at = now()
where id in ('eeeeeeee-bbbb-0000-0000-000000000002', 'eeeeeeee-bbbb-0000-0000-000000000003',
             'eeeeeeee-bbbb-0000-0000-000000000005', 'eeeeeeee-bbbb-0000-0000-000000000006',
             'eeeeeeee-bbbb-0000-0000-000000000007');

insert into public.feedback_admins (profile_id, role)
values ('eeeeeeee-bbbb-0000-0000-000000000001', 'support');

-- Both gone; one still here; and an active couple, which should not exist with both deleted but is
-- refused regardless, because purging is only ever for an archive.
insert into public.couples (id, partner_a_id, partner_b_id, status, dissolved_at) values
  ('eeeeeeee-bbbb-cccc-0000-00000000000a', 'eeeeeeee-bbbb-0000-0000-000000000002', 'eeeeeeee-bbbb-0000-0000-000000000003', 'dissolved', now()),
  ('eeeeeeee-bbbb-cccc-0000-00000000000b', 'eeeeeeee-bbbb-0000-0000-000000000004', 'eeeeeeee-bbbb-0000-0000-000000000005', 'dissolved', now()),
  ('eeeeeeee-bbbb-cccc-0000-00000000000c', 'eeeeeeee-bbbb-0000-0000-000000000006', 'eeeeeeee-bbbb-0000-0000-000000000007', 'active', null);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'eeeeeeee-bbbb-0000-0000-000000000004', true);

select throws_ok(
  $$ select * from public.admin_couple_archives('eeeeeeee-bbbb-0000-0000-000000000002') $$,
  '42501', null, 'an ordinary user cannot list somebody''s archives'
);
select throws_ok(
  $$ select public.admin_purge_couple_archive('eeeeeeee-bbbb-cccc-0000-00000000000a', 'because') $$,
  '42501', null, 'nor purge one'
);

select set_config('request.jwt.claim.sub', 'eeeeeeee-bbbb-0000-0000-000000000001', true);

select results_eq(
  $$ select couple_id, self_deleted, partner_deleted
     from public.admin_couple_archives('eeeeeeee-bbbb-0000-0000-000000000002') $$,
  $$ values ('eeeeeeee-bbbb-cccc-0000-00000000000a'::uuid, true, true) $$,
  'support sees the archive and that both partners are gone'
);
select isnt(
  (select scheduled_purge_at from public.admin_couple_archives('eeeeeeee-bbbb-0000-0000-000000000002')),
  null, 'with the timer the archive is otherwise waiting on'
);

select throws_ok(
  $$ select public.admin_purge_couple_archive('eeeeeeee-bbbb-cccc-0000-00000000000a', '  ') $$,
  '22023', null, 'a reason is required'
);
select throws_ok(
  $$ select public.admin_purge_couple_archive('eeeeeeee-bbbb-cccc-0000-00000000000b', 'asked by email') $$,
  '22023', null, 'an archive one partner can still read waits for its timer'
);
select throws_ok(
  $$ select public.admin_purge_couple_archive('eeeeeeee-bbbb-cccc-0000-00000000000c', 'asked by email') $$,
  '22023', null, 'an active couple is never purged'
);

select lives_ok(
  $$ select public.admin_purge_couple_archive('eeeeeeee-bbbb-cccc-0000-00000000000a', 'both deleted; asked by email') $$,
  'with both partners deleted, support can purge early'
);

reset role;

select is(
  (select count(*)::int from public.couples where id = 'eeeeeeee-bbbb-cccc-0000-00000000000a'),
  0, 'the couple and everything cascading from it is gone'
);
select is(
  (select count(*)::int from public.couples where id in ('eeeeeeee-bbbb-cccc-0000-00000000000b', 'eeeeeeee-bbbb-cccc-0000-00000000000c')),
  2, 'and the refused ones are untouched'
);
select results_eq(
  $$ select subject_profile_id, actor_id, reason from private.admin_audit_log
     where action = 'couple.purge' order by subject_profile_id $$,
  $$ values ('eeeeeeee-bbbb-0000-0000-000000000002'::uuid, 'eeeeeeee-bbbb-0000-0000-000000000001'::uuid, 'both deleted; asked by email'),
            ('eeeeeeee-bbbb-0000-0000-000000000003'::uuid, 'eeeeeeee-bbbb-0000-0000-000000000001'::uuid, 'both deleted; asked by email') $$,
  'recorded against both partners, naming who did it and why'
);

select * from finish();
rollback;
