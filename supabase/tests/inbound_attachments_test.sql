-- The sweep is the only thing that writes these rows, and it runs as the service role holding a
-- cron-supplied key. So the questions are the same two as everywhere else in this console: who may
-- call it, and what state is a message left in when something goes wrong.
--
-- The second matters more than usual here. A message left `pending` is retried on the next sweep,
-- which is right for a Zoho outage and wrong for a message that can never be resolved — that one
-- would be retried every five minutes forever. And a message marked `done` when the fetch failed is
-- a screenshot silently lost.

begin;
select plan(9);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values ('aaaaaaaa-5555-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','agent@inb.test','x',now(),now(),now());
insert into public.profiles (id, first_name) values ('aaaaaaaa-5555-0000-0000-000000000001','Agt')
on conflict (id) do update set first_name = excluded.first_name;
insert into public.feedback_admins (profile_id, role) values ('aaaaaaaa-5555-0000-0000-000000000001','support');

set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);

-- An emailed message with handles is marked for the sweep.
select public.ingest_support_email('<in1@x>','c@inb.test','C','Screenshot attached','See attached.',
  now(),'support@twofoldapp.com.au','2455','8823');
reset role;

select is(
  (select attachments_state from public.support_requests where message_id='<in1@x>'),
  'pending', 'an emailed message is queued for the sweep'
);

select is(
  (select folder_id from public.support_requests where message_id='<in1@x>'),
  '2455', 'with the folder id it will be asked about'
);

-- A form submission has nothing to ask Zoho about, so it is never queued.
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select public.submit_support_request('Bug Report','From the website form',null,'w@inb.test','W','web');
reset role;

select is(
  (select attachments_state from public.support_requests where email='w@inb.test'),
  'none', 'a form submission is not queued, because there is nothing to fetch'
);

-- ---------------------------------------------------------------------------
-- Who may run the sweep
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub','aaaaaaaa-5555-0000-0000-000000000001',true);

select throws_ok(
  $$ select * from public.support_messages_awaiting_attachments(10) $$,
  '42501', null, 'not even a support admin may claim the sweep''s work'
);

select throws_ok(
  $$ select public.record_inbound_attachments('00000000-0000-0000-0000-000000000001','[]'::jsonb) $$,
  '42501', null, 'nor write attachment rows, which only the sweep has seen the bytes for'
);

reset role;
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);

select is(
  (select count(*)::integer from public.support_messages_awaiting_attachments(10)),
  1, 'the sweep sees exactly the message that is waiting'
);

-- ---------------------------------------------------------------------------
-- Recording, and settling
-- ---------------------------------------------------------------------------

create temp table _m as select id from public.support_requests where message_id='<in1@x>';
grant select on _m to service_role;

select is(
  public.record_inbound_attachments((select id from _m),
    '[{"filename":"shot.png","content_type":"image/png","size_bytes":4096,"r2_key":"support/inbound/x/a.png"}]'::jsonb),
  1, 'the files are recorded'
);

-- Re-running after a partial failure re-uploads to the same key; the row must not double.
select is(
  public.record_inbound_attachments((select id from _m),
    '[{"filename":"shot.png","content_type":"image/png","size_bytes":4096,"r2_key":"support/inbound/x/a.png"}]'::jsonb),
  1, 'and a re-run writes no second row for the same object'
);

reset role;

select is(
  (select count(*)::integer from public.support_attachments where r2_key='support/inbound/x/a.png'),
  1, 'so one attachment stays one attachment however many times the sweep retries'
);

reset role;
select * from finish();
rollback;
