-- `ingest_support_email` takes the sender's address from its argument, which `submit_support_request`
-- deliberately refuses to do. That is safe only because the one caller is an edge function holding
-- the service key, having already verified the delivery came from Zoho — so the grant is the whole
-- of the protection and is the first thing pinned here.
--
-- Then the redelivery. A webhook that is retried, or a mailbox rule that fires twice, sends the same
-- message again; without the unique message id that is a second ticket for one email, and a support
-- queue that invents work is one people stop trusting.

begin;
select plan(9);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('33333333-dddd-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'writer@ingest.test', 'x', now(), now(), now()),
  ('33333333-dddd-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'known@ingest.test', 'x', now(), now(), now());

insert into public.profiles (id, first_name) values
  ('33333333-dddd-0000-0000-000000000001', 'Wri'),
  ('33333333-dddd-0000-0000-000000000002', 'Kno')
on conflict (id) do update set first_name = excluded.first_name;

-- ---------------------------------------------------------------------------
-- Only the service role may forge an address
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', '33333333-dddd-0000-0000-000000000001', true);

select throws_ok(
  $$ select public.ingest_support_email('<a@x>', 'victim@ingest.test', null, 'hi', 'body') $$,
  '42501', null, 'a signed-in user cannot file a ticket as somebody else'
);

set local role anon;
select throws_ok(
  $$ select public.ingest_support_email('<b@x>', 'victim@ingest.test', null, 'hi', 'body') $$,
  '42501', null, 'and nor can an anonymous caller'
);

-- ---------------------------------------------------------------------------
-- The edge function's own path
-- ---------------------------------------------------------------------------

reset role;
set local role service_role;

select ok(
  public.ingest_support_email('<m1@example.com>', 'known@ingest.test', 'Kno Wn', 'Cannot sign in', 'It just spins.') is not null,
  'the service role can record an emailed request'
);

reset role;

select is(
  (select source from public.support_requests where message_id = '<m1@example.com>'),
  'email', 'recorded as email, not as a form submission'
);

-- Matched at write time when the address is already an account, so the console can link straight
-- through without the reader doing it by eye.
select is(
  (select profile_id from public.support_requests where message_id = '<m1@example.com>'),
  '33333333-dddd-0000-0000-000000000002'::uuid,
  'and attached to the account that address belongs to'
);

select is(
  (select category from public.support_requests where message_id = '<m1@example.com>'),
  'Email', 'categorised by where it came from rather than guessed from the subject'
);

-- ---------------------------------------------------------------------------
-- A redelivery is not a second ticket
-- ---------------------------------------------------------------------------

set local role service_role;
select ok(
  public.ingest_support_email('<m1@example.com>', 'known@ingest.test', 'Kno Wn', 'Cannot sign in', 'It just spins.') is null,
  'the same message id returns nothing rather than inserting again'
);
reset role;

select is(
  (select count(*)::integer from public.support_requests where message_id = '<m1@example.com>'),
  1, 'so one email is one ticket, however many times it is delivered'
);

-- Two different messages with no id at all must both land — Postgres treats nulls as distinct in a
-- unique index, which is what makes the id optional for the forms that have none.
set local role service_role;
select public.ingest_support_email(null, 'a@ingest.test', null, 's', 'one');
select public.ingest_support_email(null, 'b@ingest.test', null, 's', 'two');
reset role;

select is(
  (select count(*)::integer from public.support_requests where message_id is null and email in ('a@ingest.test','b@ingest.test')),
  2, 'and messages with no id do not collide with each other'
);

reset role;
select * from finish();
rollback;
