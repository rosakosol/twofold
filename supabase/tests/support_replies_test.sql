-- Replying is the one action here that reaches a person directly, so the questions are about who
-- may do it and what the record says afterwards.
--
--   * `record_support_reply` writes a row saying we answered. Anybody who could call it could put
--     words in our mouth in the conversation history, so it is service-role only — the edge
--     function verifies the admin with the CALLER's client before reaching for the service key.
--
--   * Our own reply must not reopen the conversation. Reopening is what an incoming message does;
--     a function that set `status` unconditionally would undo, moments later, the close performed
--     by the same call.
--
--   * And the audit row names the admin. It is written from the service role, where auth.uid() is
--     null, so the actor has to be carried — the same bug that stopped account deletion working.

begin;
select plan(10);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('77777777-2222-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','agent@reply.test','x',now(),now(),now()),
  ('77777777-2222-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','cust@reply.test','x',now(),now(),now());
insert into public.profiles (id, first_name) values
  ('77777777-2222-0000-0000-000000000001','Agt'), ('77777777-2222-0000-0000-000000000002','Cus')
on conflict (id) do update set first_name = excluded.first_name;
insert into public.feedback_admins (profile_id, role) values ('77777777-2222-0000-0000-000000000001','support');

set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select public.ingest_support_email('<r1@x>','cust@reply.test','Cus','Cannot sign in','It spins.',now(),'support@twofoldapp.com.au');
reset role;

create temp table _th as select id, token from public.support_threads where email='cust@reply.test';
grant select on _th to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Who may record a reply
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub','77777777-2222-0000-0000-000000000001',true);

-- Even a support admin cannot, directly. The mail has to actually go first, and only the edge
-- function knows whether it did.
select throws_ok(
  format($$ select public.record_support_reply(%L,'77777777-2222-0000-0000-000000000001','hello') $$,
         (select id from _th)),
  '42501', null, 'not even a support admin may record a reply directly'
);

-- ---------------------------------------------------------------------------
-- What the edge function does
-- ---------------------------------------------------------------------------

reset role;
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);

select throws_ok(
  format($$ select public.record_support_reply(%L, null, 'hello') $$, (select id from _th)),
  '22023', null, 'and the service role must say who it is acting for'
);

select throws_ok(
  format($$ select public.record_support_reply(%L,'77777777-2222-0000-0000-000000000001','   ') $$,
         (select id from _th)),
  '22023', null, 'an empty reply is refused'
);

select ok(
  public.record_support_reply((select id from _th),'77777777-2222-0000-0000-000000000001',
    'Try signing out and back in.', true, 'walked them through it') is not null,
  'a reply is recorded'
);
reset role;

-- ---------------------------------------------------------------------------
-- What the conversation looks like afterwards
-- ---------------------------------------------------------------------------

select is(
  (select direction from public.support_requests where thread_id=(select id from _th) order by seq desc limit 1),
  'outbound', 'the newest message is ours, so the thread reads as an exchange'
);

select is(
  (select status from public.support_threads where id=(select id from _th)),
  'closed', 'and closing with the reply is one action, not two'
);

select is(
  (select handled_by from public.support_threads where id=(select id from _th)),
  '77777777-2222-0000-0000-000000000001'::uuid,
  'attributed to the admin who sent it'
);

select is(
  (select actor_id from private.admin_audit_log where action='support.reply' limit 1),
  '77777777-2222-0000-0000-000000000001'::uuid,
  'and the audit row names them too, not the service role'
);

-- ---------------------------------------------------------------------------
-- Replying without closing
-- ---------------------------------------------------------------------------

set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select public.record_support_reply((select id from _th),'77777777-2222-0000-0000-000000000001',
  'Could you send a screenshot?', false);
reset role;

select is(
  (select status from public.support_threads where id=(select id from _th)),
  'closed', 'a reply that does not close leaves the status alone rather than reopening it'
);

-- ---------------------------------------------------------------------------
-- What the mail needs
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub','77777777-2222-0000-0000-000000000001',true);

-- In-Reply-To comes from their last INBOUND message, never from one of ours — answering our own
-- reply would thread the conversation to itself in their client.
select is(
  public.support_thread_for_reply((select id from _th)) #>> '{last_inbound_message_id}',
  '<r1@x>', 'the reply answers their last message, not ours'
);

reset role;
select * from finish();
rollback;
