-- A new feature request starts as a new feature request (20261115000000).
--
-- The insert policy only checks the author, so before this a signed-in user could post straight to
-- the table with a request already 'released', pinned, carrying any vote count, merged into another,
-- or dated in the future — which also held the 15-minute owner edit window open forever. Whatever
-- is sent, a non-admin's row now arrives in the state a new request is in. Admins are unaffected.

begin;
select plan(9);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', email, 'x', now(), now(), now()
from (values
  ('f0f0f0f0-0000-4000-8000-000000000001'::uuid, 'member@features.test'),
  ('f0f0f0f0-0000-4000-8000-000000000002'::uuid, 'admin@features.test')
) as v(id, email);
insert into public.profiles (id, first_name) values
  ('f0f0f0f0-0000-4000-8000-000000000001', 'Member'),
  ('f0f0f0f0-0000-4000-8000-000000000002', 'Admin')
on conflict (id) do update set first_name = excluded.first_name;
insert into public.feedback_admins (profile_id, role) values ('f0f0f0f0-0000-4000-8000-000000000002', 'content');

-- ---------------------------------------------------------------------------
-- A member's forged row is reset
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"f0f0f0f0-0000-4000-8000-000000000001","role":"authenticated"}', true);

insert into public.feature_requests
  (title, slug, description, category, author_id, status, is_pinned, upvote_count, comment_count, created_at)
values
  ('Forged request', 'forged-request', 'x', 'flights', 'f0f0f0f0-0000-4000-8000-000000000001',
   'released', true, 99999, 42, '2999-01-01');

reset role;

select is((select status::text from public.feature_requests where slug = 'forged-request'), 'requested',
  'the status is reset to requested');
select is((select is_pinned from public.feature_requests where slug = 'forged-request'), false, 'it is not pinned');
select is((select upvote_count from public.feature_requests where slug = 'forged-request'), 0, 'votes start at zero');
select is((select comment_count from public.feature_requests where slug = 'forged-request'), 0, 'comments start at zero');
select ok((select created_at <= now() from public.feature_requests where slug = 'forged-request'),
  'and it cannot be dated in the future, which kept the edit window open forever');

-- ---------------------------------------------------------------------------
-- A description has the same limit the form has
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"f0f0f0f0-0000-4000-8000-000000000001","role":"authenticated"}', true);
select throws_ok(
  format($$ insert into public.feature_requests (title, slug, description, category, author_id)
            values ('Long one', 'long-one', %L, 'flights', 'f0f0f0f0-0000-4000-8000-000000000001') $$,
         repeat('x', 4001)),
  '23514', null, 'a description over 4000 characters is refused'
);
select lives_ok(
  format($$ insert into public.feature_requests (title, slug, description, category, author_id)
            values ('Just fits', 'just-fits', %L, 'flights', 'f0f0f0f0-0000-4000-8000-000000000001') $$,
         repeat('x', 4000)),
  'and 4000 exactly is fine'
);
reset role;

-- ---------------------------------------------------------------------------
-- An admin's row is left as written
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"f0f0f0f0-0000-4000-8000-000000000002","role":"authenticated"}', true);
insert into public.feature_requests (title, slug, description, category, author_id, status, is_pinned)
values ('Admin request', 'admin-request', '', 'flights', 'f0f0f0f0-0000-4000-8000-000000000002', 'planned', true);
reset role;

select is((select status::text from public.feature_requests where slug = 'admin-request'), 'planned',
  'an admin can still create a request in any state');
select is((select is_pinned from public.feature_requests where slug = 'admin-request'), true, 'including pinned');

select * from finish();
rollback;
