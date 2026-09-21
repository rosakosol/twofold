-- Splitting one admin roster into three roles is only safe if the split is invisible to everything
-- that already depended on it. Two ways that goes wrong, and both are silent:
--
--   * `is_feedback_admin()` stops returning true for someone who had it. Roughly fifteen policy
--     clauses across five migrations gate game content, FAQ entries and daily questions on that
--     function, so the failure looks like "the admin console stopped saving" with no error that
--     names a role.
--
--   * `is_feedback_admin()` starts returning true for someone who never had it. A billing-only
--     admin -- who exists so that seeing the AeroAPI bill does not require being trusted with
--     anybody's account -- silently gains write access to every deck in the app, because the old
--     body only asked whether a row existed and never looked at what it granted.
--
-- The second is the reason the function body was narrowed at all, so it is the one worth pinning.

begin;
select plan(12);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('cccccccc-7777-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'content@adminroles.test', 'x', now(), now(), now()),
  ('cccccccc-7777-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'billing@adminroles.test', 'x', now(), now(), now()),
  ('cccccccc-7777-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'all@adminroles.test', 'x', now(), now(), now()),
  ('cccccccc-7777-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'nobody@adminroles.test', 'x', now(), now(), now());

-- A trigger on auth.users already created these rows.
insert into public.profiles (id, first_name) values
  ('cccccccc-7777-0000-0000-000000000001', 'Con'),
  ('cccccccc-7777-0000-0000-000000000002', 'Bill'),
  ('cccccccc-7777-0000-0000-000000000003', 'Alba'),
  ('cccccccc-7777-0000-0000-000000000004', 'Nemo')
on conflict (id) do update set first_name = excluded.first_name;

insert into public.feedback_admins (profile_id, role) values
  ('cccccccc-7777-0000-0000-000000000001', 'content'),
  ('cccccccc-7777-0000-0000-000000000002', 'billing'),
  ('cccccccc-7777-0000-0000-000000000003', 'content'),
  ('cccccccc-7777-0000-0000-000000000003', 'support'),
  ('cccccccc-7777-0000-0000-000000000003', 'billing');

-- ---------------------------------------------------------------------------
-- The pre-existing role keeps working, and grants only itself
-- ---------------------------------------------------------------------------

select ok(public.is_feedback_admin('cccccccc-7777-0000-0000-000000000001'),
  'a content admin is still a feedback admin');
select ok(not public.is_support_admin('cccccccc-7777-0000-0000-000000000001'),
  'content does not grant support');
select ok(not public.is_billing_admin('cccccccc-7777-0000-0000-000000000001'),
  'content does not grant billing');

-- ---------------------------------------------------------------------------
-- The failure this split exists to prevent
-- ---------------------------------------------------------------------------

select ok(not public.is_feedback_admin('cccccccc-7777-0000-0000-000000000002'),
  'a billing-only admin cannot write game content');
select ok(not public.is_support_admin('cccccccc-7777-0000-0000-000000000002'),
  'a billing-only admin cannot read accounts');
select ok(public.is_billing_admin('cccccccc-7777-0000-0000-000000000002'),
  'a billing-only admin can see spend');

-- ---------------------------------------------------------------------------
-- Roles accumulate rather than replace -- the whole reason for a composite key
-- ---------------------------------------------------------------------------

select ok(public.is_feedback_admin('cccccccc-7777-0000-0000-000000000003'), 'all three: content');
select ok(public.is_support_admin('cccccccc-7777-0000-0000-000000000003'), 'all three: support');
select ok(public.is_billing_admin('cccccccc-7777-0000-0000-000000000003'), 'all three: billing');

-- ---------------------------------------------------------------------------
-- Everyone else
-- ---------------------------------------------------------------------------

select ok(not public.is_feedback_admin('cccccccc-7777-0000-0000-000000000004'),
  'a non-admin is not a feedback admin');
select ok(not public.is_support_admin('cccccccc-7777-0000-0000-000000000004'),
  'a non-admin is not a support admin');

-- The functions default to auth.uid(), which is null in this session. A null uid must not match a
-- row -- this is the anon/expired-token case, and it has to fail closed.
select ok(not public.is_billing_admin(),
  'no session is not an admin');

select * from finish();
rollback;
