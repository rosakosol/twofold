-- A provider signing in to a password account ends the password (20261124000400).

begin;
select plan(7);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', email, 'hash', now(), now(), now()
from (values
  ('b2b2b2b2-0000-4000-8000-000000000001'::uuid, 'squatted@link.test'),
  ('b2b2b2b2-0000-4000-8000-000000000002'::uuid, 'plain@link.test'),
  ('b2b2b2b2-0000-4000-8000-000000000003'::uuid, 'provider@link.test')
) as v(id, email);

insert into auth.sessions (id, user_id) values
  ('c2c2c2c2-0000-4000-8000-000000000001', 'b2b2b2b2-0000-4000-8000-000000000001'),
  ('c2c2c2c2-0000-4000-8000-000000000002', 'b2b2b2b2-0000-4000-8000-000000000002'),
  ('c2c2c2c2-0000-4000-8000-000000000003', 'b2b2b2b2-0000-4000-8000-000000000003');

insert into auth.identities (provider_id, user_id, identity_data, provider, created_at, updated_at) values
  ('b2b2b2b2-0000-4000-8000-000000000001', 'b2b2b2b2-0000-4000-8000-000000000001', '{"email":"squatted@link.test"}', 'email', now(), now()),
  ('b2b2b2b2-0000-4000-8000-000000000002', 'b2b2b2b2-0000-4000-8000-000000000002', '{"email":"plain@link.test"}', 'email', now(), now());

select is((select encrypted_password from auth.users where id = 'b2b2b2b2-0000-4000-8000-000000000001'), 'hash',
  'an email identity on its own changes nothing');

insert into auth.identities (provider_id, user_id, identity_data, provider, created_at, updated_at) values
  ('google-sub-1', 'b2b2b2b2-0000-4000-8000-000000000001', '{"email":"squatted@link.test"}', 'google', now(), now());

select is((select encrypted_password from auth.users where id = 'b2b2b2b2-0000-4000-8000-000000000001'), null,
  'a provider linking to a password account clears the password');
select is((select count(*)::int from auth.sessions where user_id = 'b2b2b2b2-0000-4000-8000-000000000001'), 0,
  'and ends the sessions from before it');
select is((select count(*)::int from auth.identities where user_id = 'b2b2b2b2-0000-4000-8000-000000000001'), 2,
  'the email identity stays, so the owner can still reset a password');

select is((select encrypted_password from auth.users where id = 'b2b2b2b2-0000-4000-8000-000000000002'), 'hash',
  'another account is not touched');
select is((select count(*)::int from auth.sessions where user_id = 'b2b2b2b2-0000-4000-8000-000000000002'), 1,
  'nor are its sessions');

insert into auth.identities (provider_id, user_id, identity_data, provider, created_at, updated_at) values
  ('google-sub-3', 'b2b2b2b2-0000-4000-8000-000000000003', '{"email":"provider@link.test"}', 'google', now(), now());
select is((select count(*)::int from auth.sessions where user_id = 'b2b2b2b2-0000-4000-8000-000000000003'), 1,
  'a first provider sign-in with no email identity changes nothing');

select * from finish();
rollback;
