-- Threading is derived, not read: Zoho's webhook sends no In-Reply-To or References, so the key is
-- the subject with reply prefixes stripped plus the sender. That makes the normalisation itself the
-- thing under test — get it wrong in either direction and the queue is unusable. Too loose and two
-- people's unrelated mail merges; too tight and every reply is a new ticket, which is the state this
-- replaces.
--
-- And reopening. Answering somebody, closing the ticket, then receiving "actually it is still
-- broken" must put that conversation back in front of whoever is reading the queue. Without it the
-- reply lands on a closed thread, filtered out of the default view, unanswered and invisible — the
-- single worst outcome available to a support queue.

begin;
select plan(12);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('44444444-eeee-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'agent@threads.test', 'x', now(), now(), now());
insert into public.profiles (id, first_name) values ('44444444-eeee-0000-0000-000000000001', 'Agt')
on conflict (id) do update set first_name = excluded.first_name;
insert into public.feedback_admins (profile_id, role) values ('44444444-eeee-0000-0000-000000000001', 'support');

-- ---------------------------------------------------------------------------
-- The key
-- ---------------------------------------------------------------------------

select is(
  private.support_thread_key('Re: Cannot sign in', 'jo@x.test'),
  private.support_thread_key('Cannot sign in', 'Jo@X.test'),
  'a reply threads onto what it replies to, whatever case the address arrives in'
);

select is(
  private.support_thread_key('RE: Re: Fwd: Cannot  sign in', 'jo@x.test'),
  private.support_thread_key('Cannot sign in', 'jo@x.test'),
  'and so does a long chain, with collapsed whitespace'
);

select is(
  private.support_thread_key('Re[2]: Cannot sign in', 'jo@x.test'),
  private.support_thread_key('Cannot sign in', 'jo@x.test'),
  'including Outlook''s numbered form'
);

select isnt(
  private.support_thread_key('Cannot sign in', 'jo@x.test'),
  private.support_thread_key('Cannot sign in', 'sam@x.test'),
  'but two people writing the same subject are two conversations'
);

select isnt(
  private.support_thread_key('Cannot sign in', 'jo@x.test'),
  private.support_thread_key('Billing question', 'jo@x.test'),
  'and one person writing about two things is two conversations'
);

-- "Research" must not lose its first two letters to the prefix stripper.
select is(
  private.support_thread_key('Research results', 'jo@x.test'),
  'research results|jo@x.test',
  'a subject that merely starts with those letters is left alone'
);

-- ---------------------------------------------------------------------------
-- A conversation
-- ---------------------------------------------------------------------------

set local role service_role;
select public.ingest_support_email('<m1@x>', 'jo@x.test', 'Jo', 'Cannot sign in', 'It spins forever.');
select public.ingest_support_email('<m2@x>', 'jo@x.test', 'Jo', 'Re: Cannot sign in', 'Still broken.');
reset role;

select is(
  (select count(distinct thread_key)::integer from public.support_requests where email = 'jo@x.test'),
  1, 'two messages, one conversation'
);

-- ---------------------------------------------------------------------------
-- Closing acts on the conversation
-- ---------------------------------------------------------------------------

-- The ids are resolved as the owner, because `authenticated` cannot read this table at all — that
-- is the point of it having no select policy, and a test that reached in directly would be testing
-- a permission the console does not have either.
create temp table _ids as
  select message_id, id from public.support_requests where email = 'jo@x.test';
grant select on _ids to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', '44444444-eeee-0000-0000-000000000001', true);

select lives_ok(
  format($$ select public.admin_set_support_request_status(%L, 'closed', 'sorted') $$,
         (select id from _ids where message_id = '<m1@x>')),
  'closing one message closes the thread'
);

reset role;

select is(
  (select count(*)::integer from public.support_requests where email = 'jo@x.test' and status = 'closed'),
  2, 'both messages, not just the one that was clicked'
);

-- ---------------------------------------------------------------------------
-- And a later reply reopens it
-- ---------------------------------------------------------------------------

set local role service_role;
select public.ingest_support_email('<m3@x>', 'jo@x.test', 'Jo', 'Re: Cannot sign in', 'Actually it is still broken.');
reset role;

select is(
  (select count(*)::integer from public.support_requests where email = 'jo@x.test' and status = 'open'),
  3, 'the whole conversation comes back open, so the reply is not lost behind a filter'
);

-- A redelivery of a message already seen must NOT reopen something just dealt with.
insert into _ids select message_id, id from public.support_requests
where message_id = '<m3@x>' and message_id not in (select message_id from _ids);

set local role authenticated;
select set_config('request.jwt.claim.sub', '44444444-eeee-0000-0000-000000000001', true);
select public.admin_set_support_request_status(
  (select id from _ids where message_id = '<m3@x>'), 'closed', 'sorted again');
reset role;

set local role service_role;
select public.ingest_support_email('<m3@x>', 'jo@x.test', 'Jo', 'Re: Cannot sign in', 'Actually it is still broken.');
reset role;

select is(
  (select count(*)::integer from public.support_requests where email = 'jo@x.test' and status = 'closed'),
  3, 'a redelivered message reopens nothing'
);

-- ---------------------------------------------------------------------------
-- The queue reads as conversations
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', '44444444-eeee-0000-0000-000000000001', true);

select is(
  (select thread_size from public.admin_support_requests(null, 100)
   where email = 'jo@x.test' and thread_position = 1),
  3::bigint, 'each row knows how big its conversation is, so the console can fold it'
);

reset role;
select * from finish();
rollback;
