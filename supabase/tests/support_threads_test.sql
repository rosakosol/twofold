-- Threading has two mechanisms and they are not equal.
--
-- The token is exact. Every reply we send carries one in its Reply-To (`support+t<hex>@`), Zoho
-- delivers plus-addressed mail to the base mailbox, and the webhook hands us the recipient — so a
-- reply identifies its conversation outright. It survives the case that defeats everything else:
-- somebody who rewrites the subject while replying.
--
-- The derived key is the fallback, and has to stay: a first message has no token to carry because
-- the conversation does not exist yet, and anybody replying to a pre-token address has none either.
--
-- And status lives on the thread now. It used to be copied onto every message, kept in step by an
-- UPDATE — a shape where one missed row leaves a conversation half-closed, which is a state nothing
-- in the UI can express and nobody would notice.

begin;
select plan(14);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('44444444-eeee-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','agent@threads.test','x',now(),now(),now()),
  ('44444444-eeee-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','jo@threads.test','x',now(),now(),now());
insert into public.profiles (id, first_name) values
  ('44444444-eeee-0000-0000-000000000001','Agt'), ('44444444-eeee-0000-0000-000000000002','Jo')
on conflict (id) do update set first_name = excluded.first_name;
insert into public.feedback_admins (profile_id, role) values ('44444444-eeee-0000-0000-000000000001','support');

-- ---------------------------------------------------------------------------
-- The derived key, for mail with no token
-- ---------------------------------------------------------------------------

select is(
  private.support_thread_key('Re: Cannot sign in','jo@x.test'),
  private.support_thread_key('Cannot sign in','Jo@X.test'),
  'a reply threads onto what it replies to, whatever case the address arrives in'
);

select is(
  private.support_thread_key('RE: Re: Fwd: Cannot  sign in','jo@x.test'),
  private.support_thread_key('Cannot sign in','jo@x.test'),
  'and so does a long chain, with collapsed whitespace'
);

select is(
  private.support_thread_key('Re[2]: Cannot sign in','jo@x.test'),
  private.support_thread_key('Cannot sign in','jo@x.test'),
  'including Outlook''s numbered form'
);

select isnt(
  private.support_thread_key('Cannot sign in','jo@x.test'),
  private.support_thread_key('Cannot sign in','sam@x.test'),
  'but two people writing the same subject are two conversations'
);

-- "Research" must not lose its first two letters to the prefix stripper.
select is(
  private.support_thread_key('Research results','jo@x.test'),
  'research results|jo@x.test',
  'a subject that merely starts with those letters is left alone'
);

-- ---------------------------------------------------------------------------
-- The token, read out of the recipient
-- ---------------------------------------------------------------------------

select is(private.token_from_address('support+t0123456789@twofoldapp.com.au'), '0123456789',
  'the token is read out of a plus address');

select is(private.token_from_address('Support <support+tABCDEF0123@twofoldapp.com.au>, someone@else.test'), 'ABCDEF0123',
  'and found inside a display name and a list of recipients');

select ok(private.token_from_address('support@twofoldapp.com.au') is null,
  'a plain address carries none, which is what sends resolution to the fallback');

-- ---------------------------------------------------------------------------
-- A conversation
-- ---------------------------------------------------------------------------

set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select public.ingest_support_email('<m1@x>','jo@threads.test','Jo','Cannot sign in','It spins.',now(),'support@twofoldapp.com.au');
select public.ingest_support_email('<m2@x>','jo@threads.test','Jo','Re: Cannot sign in','Still broken.',now(),'support@twofoldapp.com.au');
reset role;

select is(
  (select count(*)::integer from public.support_threads where email='jo@threads.test'),
  1, 'two messages with no token, one conversation, matched on the subject'
);

-- THE CASE THE DERIVED KEY CANNOT HANDLE. A reply whose subject has been rewritten entirely would
-- start a second conversation; the token in the Reply-To keeps it where it belongs.
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select public.ingest_support_email('<m3@x>','jo@threads.test','Jo','about that other thing','Following up.',now(),
  'support+t' || (select token from public.support_threads where email='jo@threads.test') || '@twofoldapp.com.au');
reset role;

select is(
  (select count(*)::integer from public.support_threads where email='jo@threads.test'),
  1, 'and a reply that rewrote the subject still lands in it, because the token said so'
);

-- ---------------------------------------------------------------------------
-- Status belongs to the conversation
-- ---------------------------------------------------------------------------

create temp table _t as select id from public.support_threads where email='jo@threads.test';
grant select on _t to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub','44444444-eeee-0000-0000-000000000001',true);
select lives_ok(
  format($$ select public.admin_set_support_thread_status(%L,'closed','sorted') $$, (select id from _t)),
  'a support admin can close the conversation'
);
reset role;

select is(
  (select status from public.support_threads where email='jo@threads.test'),
  'closed', 'one row changes, because there is only one place status lives'
);

-- ---------------------------------------------------------------------------
-- And a later reply reopens it
-- ---------------------------------------------------------------------------

set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select public.ingest_support_email('<m4@x>','jo@threads.test','Jo','Re: Cannot sign in','Actually it is still broken.',now(),'support@twofoldapp.com.au');
reset role;

select is(
  (select status from public.support_threads where email='jo@threads.test'),
  'open', 'so the reply is not lost behind the default filter'
);

-- A redelivery must reopen nothing. It is not news, and reopening on a duplicate is
-- indistinguishable from the customer writing again.
set local role authenticated;
select set_config('request.jwt.claim.sub','44444444-eeee-0000-0000-000000000001',true);
select public.admin_set_support_thread_status((select id from _t),'closed','sorted again');
reset role;

set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select public.ingest_support_email('<m4@x>','jo@threads.test','Jo','Re: Cannot sign in','Actually it is still broken.',now(),'support@twofoldapp.com.au');
reset role;

select is(
  (select status from public.support_threads where email='jo@threads.test'),
  'closed', 'a redelivered message reopens nothing'
);

reset role;
select * from finish();
rollback;
