-- Null onboarding_completed_at is the app's instruction to send somebody through onboarding, so the
-- two things worth pinning are that a fresh signup gets null (the web-created shape) and that the
-- owner can actually write the column afterwards.
--
-- That second one is not busywork. 20260915000000 revoked table-level UPDATE on profiles and
-- re-granted each column individually, so a new column is silently unwritable by its owner — the
-- failure would be a 42501 at the moment onboarding finishes, leaving the account permanently null
-- and looping it back into onboarding on every single launch.

begin;
select plan(5);

create extension if not exists pgtap;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('eeee0000-0000-4000-8000-00000000000a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'web@onboard.test', 'x', now(), now()),
  ('eeee0000-0000-4000-8000-00000000000b', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'other@onboard.test', 'x', now(), now())
on conflict do nothing;

select has_column('public', 'profiles', 'onboarding_completed_at',
  'profiles records whether onboarding happened, rather than inferring it from an empty name');

-- The web-signup shape: handle_new_user made the row, nothing else touched it.
select is(
  (select onboarding_completed_at from public.profiles where id = 'eeee0000-0000-4000-8000-00000000000a'),
  null,
  'a brand-new account has not completed onboarding'
);

select is(
  (select first_name from public.profiles where id = 'eeee0000-0000-4000-8000-00000000000a'),
  '',
  'and has no name, which is why the app cannot tell it apart from an SSO account by name alone'
);

-- ---------------------------------------------------------------------------
-- The owner can write it
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims = '{"sub":"eeee0000-0000-4000-8000-00000000000a","role":"authenticated"}';

select lives_ok(
  $$update public.profiles set onboarding_completed_at = now() where id = 'eeee0000-0000-4000-8000-00000000000a'$$,
  'the owner may mark their own onboarding complete — the per-column grant 20260915000000 requires is present'
);

-- RLS still scopes it to self. `profiles_update_self` matches no row for somebody else's id, so the
-- statement succeeds and updates nothing; the assertion is on the row, not on an error.
update public.profiles set onboarding_completed_at = now()
where id = 'eeee0000-0000-4000-8000-00000000000b';

reset role;
select is(
  (select onboarding_completed_at from public.profiles where id = 'eeee0000-0000-4000-8000-00000000000b'),
  null,
  'and cannot mark anybody else complete'
);

select * from finish();
rollback;
