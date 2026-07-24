-- Admin-only: merges `source_id` into `target_id` — re-points votes (skipping ones the
-- target already has, since a user can't hold two votes on the same feature) and
-- comments, marks the source closed + merged_into, and bulk-recomputes both features'
-- counts (the per-row insert/delete triggers on feature_votes/feature_comments don't
-- fire for bulk UPDATEs, so counts are recalculated directly here instead).
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

  -- All comments carry over — no uniqueness concern like votes have.
  update public.feature_comments set feature_id = target_id where feature_id = source_id;

  -- Bulk UPDATEs above don't fire the per-row count-sync triggers (those only run on
  -- INSERT/DELETE against feature_votes/feature_comments directly), so recompute both
  -- features' counts explicitly instead of trusting the triggers here.
  update public.feature_requests
  set upvote_count = (select count(*) from public.feature_votes where feature_id = target_id),
      comment_count = (select count(*) from public.feature_comments where feature_id = target_id)
  where id = target_id;

  update public.feature_requests
  set status = 'closed',
      merged_into = target_id,
      upvote_count = 0,
      comment_count = 0
  where id = source_id;
end;
$$;

grant execute on function public.merge_feature_requests(uuid, uuid) to authenticated;
