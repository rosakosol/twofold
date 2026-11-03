-- submit_support_request_with_thread also returns the conversation's reply-to token
-- (20261121000300).
--
-- The website's receipt told a visitor to reply, and the reply went to plain support@, where inbound
-- mail is matched by subject and sender. A web request has no subject, so the reply never joined the
-- request's conversation. Replies we send from the console carry `support+t<token>@` instead, which
-- resolves to the thread exactly; the receipt needs the same token, so the function hands it back.
--
-- The earlier columns keep their names and order, so a caller reading request_id and thread_id is
-- unaffected. The end of this file sends inbound mail to the token address and checks it lands in the
-- request's conversation, not a new one.

begin;
select plan(11);

select is(
  pg_get_function_result('public.submit_support_request_with_thread(text, text, text, text, text, text, uuid, text)'::regprocedure),
  'TABLE(request_id uuid, thread_id uuid, thread_token text)',
  'it returns request_id and thread_id as before, then the thread''s token'
);

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
create temporary table web_call on commit drop as
  select * from public.submit_support_request_with_thread(
    p_category => 'Bug Report', p_message => 'The widget is blank.', p_email => 'visitor@threadtoken.test',
    p_name => 'Sam', p_source => 'web');
reset role;

select is((select count(*)::int from web_call), 1, 'one row');
select is(
  (select thread_id from public.support_requests where id = (select request_id from web_call)),
  (select thread_id from web_call),
  'thread_id is still the request''s conversation'
);
select is(
  (select thread_token from web_call),
  (select token from public.support_threads where id = (select thread_id from web_call)),
  'thread_token is that conversation''s token'
);
select ok((select thread_token from web_call) ~ '^[0-9a-f]{10}$', 'and is the shape the inbound matcher reads');

-- Grants are unchanged by the drop and re-create.
select ok(not has_function_privilege('anon',
  'public.submit_support_request_with_thread(text, text, text, text, text, text, uuid, text)', 'EXECUTE'),
  'anon still cannot call it');
select ok(has_function_privilege('authenticated',
  'public.submit_support_request_with_thread(text, text, text, text, text, text, uuid, text)', 'EXECUTE'),
  'a signed-in caller still can');
select ok(has_function_privilege('service_role',
  'public.submit_support_request_with_thread(text, text, text, text, text, text, uuid, text)', 'EXECUTE'),
  'and so can the website''s service role');

-- ---------------------------------------------------------------------------
-- A reply to the receipt, addressed as its Reply-To says
-- ---------------------------------------------------------------------------

-- What ingest-support-email passes for a reply to the receipt: the visitor's address, the receipt's
-- subject with "Re:", and the Reply-To it was given in To. The subject matches no conversation, which
-- is exactly the case that used to start a new one.
create temporary table reply on commit drop as
  select public.ingest_support_email(
    p_message_id => '<reply-1@threadtoken.test>',
    p_email => 'visitor@threadtoken.test',
    p_name => 'Sam',
    p_subject => 'Re: We got your message - #ABCD1234',
    p_message => 'Here is a screenshot.',
    p_received_at => now(),
    p_to_address => 'Twofold Support <support+t' || (select thread_token from web_call) || '@twofoldapp.com.au>'
  ) as id;

select isnt((select id from reply), null, 'the reply is recorded');
select is(
  (select thread_id from public.support_requests where id = (select id from reply)),
  (select thread_id from web_call),
  'in the web request''s own conversation'
);
select is(
  (select count(*)::int from public.support_requests where thread_id = (select thread_id from web_call)),
  2,
  'which now holds the request and the reply'
);

select * from finish();
rollback;
