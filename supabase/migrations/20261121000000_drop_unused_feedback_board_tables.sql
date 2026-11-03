-- Drops four feedback-board tables that nothing reads or writes any more: developer_updates,
-- feature_bookmarks, feature_subscribers and feature_comments.
--
-- The website took Bookmarks and the admin's developer-update composer off the board (commit
-- 219915da). Comments and follows never had a screen on the site, and the iOS app and edge
-- functions have never touched any of the four. 20261120000100 already dropped the outbox that
-- developer updates and followers fed. All four tables are empty locally, and the owner decided to
-- drop them. Their rows go with them.
--
-- Feature requests and votes stay as they are: submitting, voting and moving a status on /feedback
-- is a feature people use, and none of the dependents below belong to it.
--
-- Dependents, found in pg_depend and by searching function bodies, and dropped by name here instead
-- of with CASCADE, so the drop fails loudly if something new has started to lean on them:
--
--   * trg_feature_comments_sync_count and its function sync_feature_comment_count(), which kept
--     feature_requests.comment_count in step with feature_comments.
--   * trg_feature_comments_touch. Its function, touch_updated_at(), is shared with seven other
--     tables and stays.
--   * merge_feature_requests(uuid, uuid) moved a source's comments onto the target and recounted
--     them. plpgsql bodies are not tracked in pg_depend, so it would have kept compiling and then
--     failed at the first merge. It is redefined below without the comment lines and is otherwise
--     unchanged; 20261121000100 adds the guards it was missing.
--
-- Each table's own policies, indexes and constraints go with it. Nothing references any of the four:
-- every foreign key involved points out of them, at feature_requests and profiles.
--
-- feature_requests.comment_count stays. The board and the admin table still select and show it, and
-- with no comments table it simply stays at zero. Dropping it is a site change to make separately.

drop trigger if exists trg_feature_comments_sync_count on public.feature_comments;
drop trigger if exists trg_feature_comments_touch on public.feature_comments;
drop function if exists public.sync_feature_comment_count();

create or replace function public.merge_feature_requests(source_id uuid, target_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_feedback_admin() then
    raise exception 'Only admins can merge feature requests.';
  end if;

  if source_id = target_id then
    raise exception 'Cannot merge a feature request into itself.';
  end if;

  -- Re-point votes that don't already exist on the target (a user can't hold two votes
  -- on what's about to become the same feature); drop the rest.
  update public.feature_votes v
  set feature_id = target_id
  where v.feature_id = source_id
    and not exists (
      select 1 from public.feature_votes existing
      where existing.feature_id = target_id and existing.user_id = v.user_id
    );

  delete from public.feature_votes where feature_id = source_id;

  -- The bulk UPDATE above doesn't fire the per-row count-sync trigger (it only runs on
  -- INSERT/DELETE against feature_votes), so recount the target explicitly.
  update public.feature_requests
  set upvote_count = (select count(*) from public.feature_votes where feature_id = target_id)
  where id = target_id;

  update public.feature_requests
  set status = 'closed',
      merged_into = target_id,
      upvote_count = 0,
      comment_count = 0
  where id = source_id;
end;
$$;

drop table public.developer_updates;
drop table public.feature_bookmarks;
drop table public.feature_subscribers;
drop table public.feature_comments;
