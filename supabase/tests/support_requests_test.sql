-- `submit_support_request` is callable by `anon`, because the website's form serves visitors who
-- cannot sign in — often precisely because signing in is what they are writing about. That makes it
-- the only anon-reachable write in the console's whole surface, so its two properties are the ones
-- worth pinning:
--
--   * Attribution is resolved inside the function, never taken from the call. A profile_id
--     parameter would let anybody file a ticket against anybody; a client-chosen email on a
--     signed-in request would decide where a support REPLY goes, which is worse — it would make
--     this a way to have us send mail to an address of the caller's choosing.
--   * Nobody can read the table. The messages are what people wrote to us in confidence, and there
--     is no select policy at all — reads go through is_support_admin()-gated functions.
--
-- The table is also the only place in this console that stores content rather than status, and
-- that is deliberate: the distinction is not text versus not-text, but between what somebody wrote
-- for themselves and their partner and what they deliberately wrote TO us in order to be helped.

begin;
select plan(14);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', email, 'x', now(), now(), now()
from (values
  ('22222222-cccc-0000-0000-000000000001'::uuid, 'support@tickets.test'),
  ('22222222-cccc-0000-0000-000000000002'::uuid, 'sender@tickets.test'),
  ('22222222-cccc-0000-0000-000000000003'::uuid, 'nosy@tickets.test')
) as v(id, email);

insert into public.profiles (id, first_name) values
  ('22222222-cccc-0000-0000-000000000001', 'Sam'),
  ('22222222-cccc-0000-0000-000000000002', 'Kit'),
  ('22222222-cccc-0000-0000-000000000003', 'Nos')
on conflict (id) do update set first_name = excluded.first_name;

insert into public.feedback_admins (profile_id, role)
values ('22222222-cccc-0000-0000-000000000001', 'support');

-- ---------------------------------------------------------------------------
-- A signed-in sender
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', '22222222-cccc-0000-0000-000000000002', true);

select lives_ok(
  $$ select public.submit_support_request('Bug Report', 'Flights stopped updating', 'Flights stuck', 'attacker@evil.test', 'Not Kit', 'app') $$,
  'a signed-in person can file a request'
);

reset role;

select is(
  (select profile_id from public.support_requests order by created_at desc limit 1),
  '22222222-cccc-0000-0000-000000000002'::uuid,
  'attributed to the caller, from their own JWT'
);

-- The load-bearing one. A support reply goes to this address, so a caller choosing it would turn
-- the contact form into a way to make us send mail wherever they like — with our own sending
-- domain behind it.
select is(
  (select email from public.support_requests order by created_at desc limit 1),
  'sender@tickets.test',
  'and to their ACCOUNT''s address, not the one they posted'
);

select is(
  (select source from public.support_requests order by created_at desc limit 1),
  'app', 'with the source it came from'
);

-- ---------------------------------------------------------------------------
-- A visitor with no account
-- ---------------------------------------------------------------------------

-- The claim has to be cleared as well as the role. `auth.uid()` reads request.jwt.claim.sub and
-- does not care what role is set, so `set role anon` on its own leaves the previous sender signed
-- in — and this section would then assert the anonymous path while exercising the authenticated
-- one, passing for the wrong reason.
set local role anon;
select set_config('request.jwt.claim.sub', '', true);

select lives_ok(
  $$ select public.submit_support_request('Account & Subscription', 'I cannot sign in at all', null, 'locked-out@tickets.test', 'Jo', 'web') $$,
  'and so can a visitor who cannot sign in, which is the whole reason anon may call this'
);

reset role;

select ok(
  (select profile_id from public.support_requests where source = 'web' limit 1) is null,
  'their request carries no profile, because they had no session to prove one'
);

select is(
  (select email from public.support_requests where source = 'web' limit 1),
  'locked-out@tickets.test',
  'but keeps the address they typed, which is the only way to answer them'
);

-- ---------------------------------------------------------------------------
-- Validation
-- ---------------------------------------------------------------------------

set local role anon;
select set_config('request.jwt.claim.sub', '', true);

select throws_ok(
  $$ select public.submit_support_request('Bug Report', '   ', null, 'a@b.test', null, 'web') $$,
  '22023', null, 'an empty message is refused'
);

select throws_ok(
  $$ select public.submit_support_request('Bug Report', 'hello', null, 'a@b.test', null, 'carrier-pigeon') $$,
  '22023', null, 'and an unknown source'
);

-- ---------------------------------------------------------------------------
-- Nobody reads it but support
-- ---------------------------------------------------------------------------

select throws_ok(
  $$ select * from public.support_requests $$,
  '42501', null, 'an anonymous caller cannot read what anyone wrote in'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '22222222-cccc-0000-0000-000000000003', true);

select throws_ok(
  $$ select * from public.support_requests $$,
  '42501', null, 'nor a signed-in one'
);

select throws_ok(
  $$ select * from public.admin_support_requests('open') $$,
  '42501', null, 'and the console function refuses them too'
);

-- ---------------------------------------------------------------------------
-- The queue
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '22222222-cccc-0000-0000-000000000001', true);

select is(
  (select count(*)::integer from public.admin_support_requests('open')),
  2, 'a support admin sees both, open by default'
);

-- A website submission from somebody who could not sign in still reaches their account, matched on
-- the address at read time rather than stored as a link — so a request filed before an account
-- existed resolves once it does.
select is(
  (select matched_profile_id from public.admin_support_requests('open') where source = 'app'),
  '22222222-cccc-0000-0000-000000000002'::uuid,
  'and each row points at the account it belongs to'
);

reset role;
select * from finish();
rollback;
