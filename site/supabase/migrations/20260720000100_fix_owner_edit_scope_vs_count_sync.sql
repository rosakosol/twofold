-- Bugfix: enforce_feature_request_owner_edit_scope() (20260719000400) blocked every
-- non-admin vote/comment, not just admin-only edits. sync_feature_upvote_count() and
-- sync_feature_comment_count() (20260719000500/000600) update feature_requests'
-- upvote_count/comment_count on behalf of ANY authenticated voter/commenter, but that
-- update is itself an UPDATE on feature_requests, so it re-fires this same BEFORE
-- UPDATE trigger — which then saw a non-admin's auth.uid() and a changed "counts"
-- column and rejected the write outright. Confirmed via a simulated non-admin vote:
-- "ERROR: Only admins can change status, pin, merge, author, slug, or counts...".
--
-- Fix: only enforce the column restriction on a direct, top-level update to
-- feature_requests (pg_trigger_depth() <= 1, i.e. a user's own UPDATE statement, where
-- this is the only trigger in play). An update reached via another trigger firing first
-- (pg_trigger_depth() > 1) can only be the trusted vote/comment count-sync triggers —
-- those are the only other triggers that ever write to this table — so it's safe to
-- exempt them rather than re-litigating admin-ness for a system-maintained counter.
create or replace function public.enforce_feature_request_owner_edit_scope()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.is_feedback_admin() or pg_trigger_depth() > 1 then
    return new;
  end if;

  if new.status is distinct from old.status
    or new.is_pinned is distinct from old.is_pinned
    or new.merged_into is distinct from old.merged_into
    or new.author_id is distinct from old.author_id
    or new.slug is distinct from old.slug
    or new.upvote_count is distinct from old.upvote_count
    or new.comment_count is distinct from old.comment_count
  then
    raise exception 'Only admins can change status, pin, merge, author, slug, or counts on a feature request.';
  end if;

  return new;
end;
$$;
