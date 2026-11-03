-- merge_feature_requests refuses merges that would corrupt the board (20261121000100).
--
-- It used to check only that source and target differ. Merging an already-merged request again
-- re-pointed its merged_into, so its history moved to whatever was picked second. Merging into a
-- closed or merged request moved votes onto a row the board no longer shows. The admin dialog filters
-- those out, but from a list read when it opened, so a second admin's merge in the meantime got
-- through. Each refusal is a plain `raise exception`, which the console shows word for word.

begin;
select plan(13);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', email, 'x', now(), now(), now()
from (values
  ('3e3e3e3e-0000-4000-8000-000000000001'::uuid, 'admin@mergeguard.test'),
  ('3e3e3e3e-0000-4000-8000-000000000002'::uuid, 'member@mergeguard.test')
) as v(id, email);
insert into public.profiles (id, first_name) values
  ('3e3e3e3e-0000-4000-8000-000000000001', 'Admin'),
  ('3e3e3e3e-0000-4000-8000-000000000002', 'Member')
on conflict (id) do update set first_name = excluded.first_name;
insert into public.feedback_admins (profile_id, role) values ('3e3e3e3e-0000-4000-8000-000000000001', 'content');

-- open-a and open-b are live; closed-c was closed outright; merged-d was merged into open-b.
-- Inserted as the admin: for anybody else enforce_feature_request_insert_scope resets status and
-- merged_into, and every fixture would arrive as a fresh open request.
select set_config('request.jwt.claims', '{"sub":"3e3e3e3e-0000-4000-8000-000000000001","role":"authenticated"}', true);
insert into public.feature_requests (id, author_id, title, slug, category, status, merged_into) values
  ('3e3e3e3e-0000-4000-8000-0000000000a1', '3e3e3e3e-0000-4000-8000-000000000001', 'Open A', 'merge-open-a', 'general', 'requested', null),
  ('3e3e3e3e-0000-4000-8000-0000000000b1', '3e3e3e3e-0000-4000-8000-000000000001', 'Open B', 'merge-open-b', 'general', 'planned', null),
  ('3e3e3e3e-0000-4000-8000-0000000000c1', '3e3e3e3e-0000-4000-8000-000000000001', 'Closed C', 'merge-closed-c', 'general', 'closed', null),
  ('3e3e3e3e-0000-4000-8000-0000000000d1', '3e3e3e3e-0000-4000-8000-000000000001', 'Merged D', 'merge-merged-d', 'general', 'closed',
   '3e3e3e3e-0000-4000-8000-0000000000b1'),
  -- A merged row whose status was later reopened by hand: merged_into alone has to be enough.
  ('3e3e3e3e-0000-4000-8000-0000000000e1', '3e3e3e3e-0000-4000-8000-000000000001', 'Merged E', 'merge-merged-e', 'general', 'planned',
   '3e3e3e3e-0000-4000-8000-0000000000b1');

select is(
  (select string_agg(slug || ':' || status || ':' || (merged_into is not null), ',' order by slug)
   from public.feature_requests where slug like 'merge-%'),
  'merge-closed-c:closed:false,merge-merged-d:closed:true,merge-merged-e:planned:true,merge-open-a:requested:false,merge-open-b:planned:false',
  'the fixtures are in the states the assertions below rely on'
);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"3e3e3e3e-0000-4000-8000-000000000001","role":"authenticated"}', true);

select throws_ok(
  $$ select public.merge_feature_requests('3e3e3e3e-0000-4000-8000-0000000000a1', '3e3e3e3e-0000-4000-8000-0000000000a1') $$,
  'P0001', 'Cannot merge a feature request into itself.',
  'a request cannot be merged into itself'
);
select throws_ok(
  $$ select public.merge_feature_requests('3e3e3e3e-0000-4000-8000-0000000000d1', '3e3e3e3e-0000-4000-8000-0000000000a1') $$,
  'P0001', 'This request has already been merged into another one.',
  'an already-merged request cannot be merged again'
);
select throws_ok(
  $$ select public.merge_feature_requests('3e3e3e3e-0000-4000-8000-0000000000e1', '3e3e3e3e-0000-4000-8000-0000000000a1') $$,
  'P0001', 'This request has already been merged into another one.',
  'including one whose status was reopened after the merge'
);
select throws_ok(
  $$ select public.merge_feature_requests('3e3e3e3e-0000-4000-8000-0000000000a1', '3e3e3e3e-0000-4000-8000-0000000000c1') $$,
  'P0001', 'Cannot merge into a request that is closed or has been merged.',
  'a closed request is not a merge target'
);
select throws_ok(
  $$ select public.merge_feature_requests('3e3e3e3e-0000-4000-8000-0000000000a1', '3e3e3e3e-0000-4000-8000-0000000000e1') $$,
  'P0001', 'Cannot merge into a request that is closed or has been merged.',
  'nor is a merged one, whatever its status says'
);
select throws_ok(
  $$ select public.merge_feature_requests('3e3e3e3e-0000-4000-8000-0000000000a1', '3e3e3e3e-0000-4000-8000-0000000000ff') $$,
  'P0001', 'That feature request no longer exists.',
  'a missing target is refused rather than leaving the source pointing at nothing'
);
reset role;

select is(
  (select merged_into from public.feature_requests where id = '3e3e3e3e-0000-4000-8000-0000000000d1'),
  '3e3e3e3e-0000-4000-8000-0000000000b1'::uuid,
  'the refused re-merge left the first merge where it was'
);
select is(
  (select row(status::text, merged_into)::text from public.feature_requests where id = '3e3e3e3e-0000-4000-8000-0000000000a1'),
  row('requested', null::uuid)::text,
  'and none of the refusals touched the source'
);

-- The ordinary merge still goes through.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"3e3e3e3e-0000-4000-8000-000000000001","role":"authenticated"}', true);
select lives_ok(
  $$ select public.merge_feature_requests('3e3e3e3e-0000-4000-8000-0000000000a1', '3e3e3e3e-0000-4000-8000-0000000000b1') $$,
  'an open request still merges into another open one'
);
reset role;
select is(
  (select merged_into from public.feature_requests where id = '3e3e3e3e-0000-4000-8000-0000000000a1'),
  '3e3e3e3e-0000-4000-8000-0000000000b1'::uuid,
  'and points at it'
);

-- A member is still refused, and nobody without a session can call it.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"3e3e3e3e-0000-4000-8000-000000000002","role":"authenticated"}', true);
select throws_ok(
  $$ select public.merge_feature_requests('3e3e3e3e-0000-4000-8000-0000000000b1', '3e3e3e3e-0000-4000-8000-0000000000c1') $$,
  'P0001', 'Only admins can merge feature requests.',
  'a member cannot merge'
);
reset role;
select ok(
  not has_function_privilege('anon', 'public.merge_feature_requests(uuid, uuid)', 'EXECUTE'),
  'anon cannot execute it'
);

select * from finish();
rollback;
