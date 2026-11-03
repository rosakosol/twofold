-- 20261120000100 drops the feedback board's notification outbox. Pinned here: the table, its two
-- triggers and their functions are gone, and changing a status still works. developer_updates
-- itself was dropped by 20261121000000, so posting an update is no longer asserted here.

begin;
select plan(7);

create extension if not exists pgtap;

select hasnt_table('public'::name, 'feature_notification_outbox'::name,
  'feature_notification_outbox is gone');
select hasnt_trigger('public'::name, 'developer_updates'::name, 'trg_developer_updates_notify'::name,
  'the developer-update trigger is gone');
select hasnt_trigger('public'::name, 'feature_requests'::name, 'trg_feature_requests_status_change_notify'::name,
  'the status-change trigger is gone');
select hasnt_function('public'::name, 'enqueue_developer_update_notifications'::name,
  'its developer-update function is gone');
select hasnt_function('public'::name, 'enqueue_feature_status_change_notifications'::name,
  'its status-change function is gone');

-- The tables the triggers sat on still take writes, made as a feedback admin so a status can move.
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values ('cccccccc-0b0b-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
        'authenticated', 'admin@outboxdrop.test', 'x', now(), now(), now());
-- A trigger on auth.users already created this row.
insert into public.profiles (id, first_name) values ('cccccccc-0b0b-0000-0000-000000000001', 'Ada')
on conflict (id) do update set first_name = excluded.first_name;
insert into public.feedback_admins (profile_id, role) values ('cccccccc-0b0b-0000-0000-000000000001', 'content');
set local request.jwt.claims = '{"sub": "cccccccc-0b0b-0000-0000-000000000001", "role": "authenticated"}';

select lives_ok(
  $$ insert into public.feature_requests (id, author_id, title, slug, category)
     values ('00000000-0000-0000-0000-00000000f0b2', 'cccccccc-0b0b-0000-0000-000000000001',
             'Outbox drop', 'outbox-drop', 'general') $$,
  'a feature request can still be filed'
);
select lives_ok(
  $$ update public.feature_requests set status = 'planned'
     where id = '00000000-0000-0000-0000-00000000f0b2' $$,
  'its status can still change'
);

select * from finish();
rollback;
