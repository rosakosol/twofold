-- ---------------------------------------------------------------------------
-- faq_entries: only admins write, everyone still reads
-- ---------------------------------------------------------------------------
--
-- This policy is what replaces the `admin-faq` Edge Function's shared secret — a `NEXT_PUBLIC_`
-- value inlined into a publicly fetchable JS chunk that unlocked a service-role client. The
-- protection now comes from `feedback_admins`, the access model the site already uses.
--
-- The pair that matters: a signed-in NON-admin must not be able to write. That is the case the
-- secret never covered, because holding the secret was the whole check.

begin;
select plan(6);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-1212-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin@faqwrite.test', 'x', now(), now(), now()),
  ('bbbbbbbb-1212-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'nobody@faqwrite.test', 'x', now(), now(), now());

insert into public.feedback_admins (profile_id) values ('aaaaaaaa-1212-0000-0000-000000000001')
on conflict do nothing;

insert into public.faq_entries (id, category, question, answer, sort_order)
values ('ffffffff-1212-0000-0000-00000000000f', 'Account', 'Existing question?', 'Existing answer.', 10);

-- ---------------------------------------------------------------------------
-- A signed-in non-admin
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-1212-0000-0000-000000000002","role":"authenticated"}';

select throws_ok(
  $$insert into public.faq_entries (category, question, answer, sort_order)
    values ('Billing', 'Can I write this?', 'Apparently not.', 1)$$,
  '42501',
  null,
  'a signed-in non-admin cannot create an FAQ entry'
);

select lives_ok(
  $$update public.faq_entries set answer = 'Rewritten by a stranger.'
    where id = 'ffffffff-1212-0000-0000-00000000000f'$$,
  'a non-admin update raises nothing — RLS filters the row rather than refusing'
);

select is(
  (select answer from public.faq_entries where id = 'ffffffff-1212-0000-0000-00000000000f'),
  'Existing answer.',
  'and the answer is untouched, which is what the silent no-op actually means'
);

-- Reading is public and must stay that way: /faq and the iOS Support screen both depend on it.
select cmp_ok(
  (select count(*)::int from public.faq_entries),
  '>', 0,
  'a non-admin can still read the FAQ'
);

-- ---------------------------------------------------------------------------
-- An admin
-- ---------------------------------------------------------------------------

set local request.jwt.claims = '{"sub":"aaaaaaaa-1212-0000-0000-000000000001","role":"authenticated"}';

select lives_ok(
  $$insert into public.faq_entries (category, question, answer, sort_order)
    values ('Billing', 'How do I cancel?', 'From the App Store subscriptions screen.', 1)$$,
  'an admin can create an FAQ entry'
);

select lives_ok(
  $$delete from public.faq_entries where question = 'How do I cancel?'$$,
  'and delete one'
);

select * from finish();
rollback;
