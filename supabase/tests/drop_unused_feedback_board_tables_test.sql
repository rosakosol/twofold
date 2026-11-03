-- 20261121000000 drops developer_updates, feature_bookmarks, feature_subscribers and feature_comments.
-- Pinned here: the tables and the comment-count trigger function are gone, merge_feature_requests no
-- longer reads feature_comments, and the part of the board people use still works end to end. A
-- member files a request and votes on it, the vote is counted and can be taken back, an admin moves
-- its status, and two requests can still be merged.

begin;
select plan(17);

create extension if not exists pgtap;

select hasnt_table('public'::name, 'developer_updates'::name, 'developer_updates is gone');
select hasnt_table('public'::name, 'feature_bookmarks'::name, 'feature_bookmarks is gone');
select hasnt_table('public'::name, 'feature_subscribers'::name, 'feature_subscribers is gone');
select hasnt_table('public'::name, 'feature_comments'::name, 'feature_comments is gone');
select hasnt_function('public'::name, 'sync_feature_comment_count'::name,
  'the comment-count trigger function is gone');
select ok(
  not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname not in ('pg_catalog', 'information_schema')
      and p.prosrc ~ '(developer_updates|feature_bookmarks|feature_subscribers|feature_comments)'
  ),
  'no function body still names a dropped table'
);
select has_function('public'::name, 'touch_updated_at'::name, 'the shared touch_updated_at stays');

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', email, 'x', now(), now(), now()
from (values
  ('fbfbfbfb-0000-4000-8000-000000000001'::uuid, 'member@boarddrop.test'),
  ('fbfbfbfb-0000-4000-8000-000000000002'::uuid, 'admin@boarddrop.test')
) as v(id, email);
-- A trigger on auth.users already created these rows.
insert into public.profiles (id, first_name) values
  ('fbfbfbfb-0000-4000-8000-000000000001', 'Member'),
  ('fbfbfbfb-0000-4000-8000-000000000002', 'Admin')
on conflict (id) do update set first_name = excluded.first_name;
insert into public.feedback_admins (profile_id, role) values ('fbfbfbfb-0000-4000-8000-000000000002', 'content');

-- ---------------------------------------------------------------------------
-- A member files a request and votes on it
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"fbfbfbfb-0000-4000-8000-000000000001","role":"authenticated"}', true);

select lives_ok(
  $$ insert into public.feature_requests (id, author_id, title, slug, category)
     values ('fbfbfbfb-0000-4000-8000-0000000000f1', 'fbfbfbfb-0000-4000-8000-000000000001',
             'Board drop', 'board-drop', 'general') $$,
  'a member can still file a feature request'
);
select lives_ok(
  $$ insert into public.feature_votes (feature_id, user_id)
     values ('fbfbfbfb-0000-4000-8000-0000000000f1', 'fbfbfbfb-0000-4000-8000-000000000001') $$,
  'and vote on it'
);
select is((select upvote_count from public.feature_requests where id = 'fbfbfbfb-0000-4000-8000-0000000000f1'),
  1, 'the vote is counted');
select lives_ok(
  $$ delete from public.feature_votes
     where feature_id = 'fbfbfbfb-0000-4000-8000-0000000000f1' and user_id = 'fbfbfbfb-0000-4000-8000-000000000001' $$,
  'and taken back'
);
select is((select upvote_count from public.feature_requests where id = 'fbfbfbfb-0000-4000-8000-0000000000f1'),
  0, 'which uncounts it');
insert into public.feature_votes (feature_id, user_id)
values ('fbfbfbfb-0000-4000-8000-0000000000f1', 'fbfbfbfb-0000-4000-8000-000000000001');

reset role;

-- ---------------------------------------------------------------------------
-- An admin moves its status and merges another request into it
-- ---------------------------------------------------------------------------

-- A second request, filed directly, to merge into the first.
insert into public.feature_requests (id, author_id, title, slug, category)
values ('fbfbfbfb-0000-4000-8000-0000000000f2', 'fbfbfbfb-0000-4000-8000-000000000002',
        'Board drop twin', 'board-drop-twin', 'general');
insert into public.feature_votes (feature_id, user_id)
values ('fbfbfbfb-0000-4000-8000-0000000000f2', 'fbfbfbfb-0000-4000-8000-000000000002');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"fbfbfbfb-0000-4000-8000-000000000002","role":"authenticated"}', true);

select lives_ok(
  $$ update public.feature_requests set status = 'planned' where id = 'fbfbfbfb-0000-4000-8000-0000000000f1' $$,
  'an admin can still change its status'
);
select lives_ok(
  $$ select public.merge_feature_requests('fbfbfbfb-0000-4000-8000-0000000000f2', 'fbfbfbfb-0000-4000-8000-0000000000f1') $$,
  'and merge another request into it, with no comments table to move'
);

reset role;

select is((select status::text from public.feature_requests where id = 'fbfbfbfb-0000-4000-8000-0000000000f1'),
  'planned', 'the status change stuck');
select is((select upvote_count from public.feature_requests where id = 'fbfbfbfb-0000-4000-8000-0000000000f1'),
  2, 'the merged vote moved across and is counted');
select is(
  (select row(status::text, merged_into)::text from public.feature_requests where id = 'fbfbfbfb-0000-4000-8000-0000000000f2'),
  row('closed', 'fbfbfbfb-0000-4000-8000-0000000000f1'::uuid)::text,
  'the source is closed and points at its target'
);

select * from finish();
rollback;
