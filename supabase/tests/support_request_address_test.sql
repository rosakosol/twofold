-- An anonymous support request's address is one plain address, or the request is refused.
--
-- The website route validates the format, but the function must not rely on that: the address it
-- stores is the `to` of every reply. denomailer writes the
-- display-name half of `Name <addr>` into the message unescaped, so a stored address with line
-- breaks in it is header, body, and SMTP-command injection the moment an admin answers.

begin;
select plan(8);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values ('c0a5c0a5-add2-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'member@address.test', 'x', now(), now(), now());
insert into public.profiles (id, first_name) values ('c0a5c0a5-add2-4000-8000-000000000001', 'Kit')
on conflict (id) do update set first_name = excluded.first_name;

-- As the website's route calls it: the service role, with no user (20261115000000 took the anon
-- grant away).
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

select throws_ok(
  $$ select public.submit_support_request('Other', 'hi', null,
       E'x\r\n\r\nInjected body\r\n.\r\nMAIL FROM:support@twofoldapp.com.au <victim@address.test>', null, 'web') $$,
  '22023', null,
  'an address carrying line breaks before a bracketed address is refused'
);
select throws_ok(
  $$ select public.submit_support_request('Other', 'hi', null, 'Someone <someone@address.test>', null, 'web') $$,
  '22023', null,
  'a display name is refused'
);
select throws_ok(
  $$ select public.submit_support_request('Other', 'hi', null, 'a@address.test, b@address.test', null, 'web') $$,
  '22023', null,
  'a list is refused'
);
select throws_ok(
  $$ select public.submit_support_request('Other', 'hi', null, E'a@address.test\nBcc: b@address.test', null, 'web') $$,
  '22023', null,
  'a trailing header is refused'
);
select throws_ok(
  $$ select public.submit_support_request('Other', 'hi', null, null, null, 'web') $$,
  '22023', null,
  'no address at all is refused with the same error rather than a constraint failure'
);
select lives_ok(
  $$ select public.submit_support_request('Other', 'plain address', null, '  first.last+tag@mail.address.test ', null, 'web') $$,
  'an ordinary address still files'
);

reset role;

select is(
  (select t.email from public.support_threads t
   join public.support_requests r on r.thread_id = t.id
   where r.message = 'plain address'),
  'first.last+tag@mail.address.test',
  'and is what the thread will be replied to'
);

-- Signed in: the posted address is ignored entirely, so a malformed one costs nothing.
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"c0a5c0a5-add2-4000-8000-000000000001","role":"authenticated"}', true);
select lives_ok(
  $$ select public.submit_support_request('Other', 'signed in', null, E'junk\r\n', null, 'app') $$,
  'a signed-in caller is unaffected by whatever they post as an address'
);
reset role;

select * from finish();
rollback;
