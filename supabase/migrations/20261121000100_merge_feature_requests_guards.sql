-- merge_feature_requests refuses merges that leave the board wrong (NEW-1 / SITE-15).
--
-- The only check it made was source <> target. So:
--
--   * Merging a request that had already been merged ran again. merged_into was re-pointed at the
--     second target, so the history of where its votes went was overwritten.
--   * Merging into a closed or merged request moved the votes onto a row the board no longer lists.
--     The votes vanished from view, and the request people were directed to was a dead end.
--   * A target id that didn't exist failed on the merged_into foreign key with a constraint name
--     instead of a sentence.
--
-- The console's merge dialog leaves closed and merged requests out of its picker, but the picker
-- comes from a list read when the dialog opened. If another admin merges or closes one of the two
-- in the meantime, the old function let the merge through. The function is the only place this can
-- be decided, so it now locks both rows and checks them there. The two rows are locked in id order,
-- so two merges running at once in opposite directions wait for each other instead of deadlocking.
-- The second one then sees the first one's result and is refused.
--
-- Every refusal is a plain `raise exception` (P0001). The console's describeDbError shows that text
-- word for word, so the wording below is what an admin reads.
--
-- The grants are also fixed. The function was created before Supabase's default privileges were
-- revoked, so anon and PUBLIC could still execute it. The is_feedback_admin() check refused them,
-- but there is no reason for an anonymous caller to reach it at all.

create or replace function public.merge_feature_requests(source_id uuid, target_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_source public.feature_requests%rowtype;
  v_target public.feature_requests%rowtype;
begin
  if not public.is_feedback_admin() then
    raise exception 'Only admins can merge feature requests.';
  end if;

  if source_id = target_id then
    raise exception 'Cannot merge a feature request into itself.';
  end if;

  -- Both rows, locked in a fixed order, before anything is read from them.
  perform 1 from public.feature_requests
  where id in (source_id, target_id)
  order by id
  for update;

  select * into v_source from public.feature_requests where id = source_id;
  select * into v_target from public.feature_requests where id = target_id;

  if v_source.id is null or v_target.id is null then
    raise exception 'That feature request no longer exists.';
  end if;

  if v_source.merged_into is not null then
    raise exception 'This request has already been merged into another one.';
  end if;

  if v_target.merged_into is not null or v_target.status = 'closed' then
    raise exception 'Cannot merge into a request that is closed or has been merged.';
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

revoke all on function public.merge_feature_requests(uuid, uuid) from public, anon;
grant execute on function public.merge_feature_requests(uuid, uuid) to authenticated;
