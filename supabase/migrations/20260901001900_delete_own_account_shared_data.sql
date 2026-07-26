-- Lets someone delete the shared archive at the same time as their account.
--
-- Background: `delete_own_account()` (20260901001500) deliberately leaves shared trips/memories/
-- flights alone, because they're the *other* partner's history too — and `leave_couple` archives
-- rather than deletes for the same reason. The gap that leaves: `delete_dissolved_couple_data`
-- (20260712120000) is the only way to actually remove a shared archive, it lives behind
-- Settings → Archived Data, and a deleted account can never sign in to reach it. So the moment
-- you delete your account is the moment you permanently lose the ability to delete anything you
-- shared — your ex-partner becomes its sole custodian, whether or not either of you wanted that.
--
-- This adds an opt-in `p_delete_shared_data` flag to `delete_own_account`, so the choice is
-- offered while the user can still make it. It grants no new capability: either partner could
-- already wipe a dissolved couple's data unilaterally from Settings. It just makes that same
-- action reachable at the one moment it would otherwise become impossible.
--
-- Also extracts the purge itself into `purge_couple_data()` so the "what gets deleted" logic
-- exists once, shared by both callers, instead of being copied and left to drift.

-- ---------------------------------------------------------------------------
-- Shared purge. NO authorisation checks of its own — both callers below do their own, and this
-- is deliberately not executable by `authenticated` (see the revoke) so it can only ever be
-- reached through one of them.
-- ---------------------------------------------------------------------------
create or replace function public.purge_couple_data(p_couple_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Storage objects aren't FK-linked to couples, so they have to go explicitly. Everything
  -- else (trips, memories, flights + their events/prefs/documents, game sessions + rounds +
  -- responses) is `on delete cascade` back to couples.id, so deleting the couple row is enough.
  perform set_config('storage.allow_delete_query', 'true', true);
  delete from storage.objects where bucket_id = 'memory-photos' and (storage.foldername(name))[1] = p_couple_id::text;
  delete from storage.objects where bucket_id = 'flight-documents' and (storage.foldername(name))[1] = p_couple_id::text;
  delete from storage.objects where bucket_id = 'drawing-pads' and (storage.foldername(name))[1] = p_couple_id::text;

  delete from public.couples where id = p_couple_id;
end;
$$;

revoke all on function public.purge_couple_data(uuid) from public;

-- ---------------------------------------------------------------------------
-- Settings → Archived Data. Unchanged behaviour; the body now just delegates.
-- ---------------------------------------------------------------------------
create or replace function public.delete_dissolved_couple_data(p_couple_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_couple public.couples;
  v_caller_id uuid := auth.uid();
begin
  if v_caller_id is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_couple from public.couples where id = p_couple_id for update;

  if not found then
    raise exception 'Couple not found';
  end if;

  if v_couple.partner_a_id <> v_caller_id and v_couple.partner_b_id <> v_caller_id then
    raise exception 'You are not a member of this couple';
  end if;

  -- Never on a couple that's still active — dissolving is the deliberate, separate first step
  -- (leave_couple), so a permanent delete can never be triggered accidentally on live data.
  if v_couple.status <> 'dissolved' then
    raise exception 'Only a dissolved couple''s data can be permanently deleted';
  end if;

  perform public.purge_couple_data(p_couple_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- Account deletion. The signature changes, so the old zero-argument version has to be dropped
-- rather than replaced: leaving both would make an unqualified `delete_own_account()` call
-- ambiguous, and the Edge Function calls it exactly that way.
-- ---------------------------------------------------------------------------
drop function if exists public.delete_own_account();

create or replace function public.delete_own_account(p_delete_shared_data boolean default false)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_couple_id uuid;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  -- Dissolve any couple this profile is still actively part of first — the same status flip
  -- `leave_couple` performs — so the remaining partner gets the normal "partner left"
  -- experience instead of their partner's name/photo silently disappearing with no signal
  -- anything happened. Still done even when purging below, so that a partner who happens to be
  -- looking at the app sees the departure rather than the couple vanishing mid-session.
  for v_couple_id in
    select id from public.couples
    where (partner_a_id = v_uid or partner_b_id = v_uid) and status = 'active'
  loop
    update public.couples
    set status = 'dissolved', dissolved_at = now(), dissolved_by = v_uid
    where id = v_couple_id;
  end loop;

  -- Opt-in: permanently delete every shared archive this profile is part of — the one just
  -- dissolved above, and any older ones still sitting in Settings → Archived Data. All of them,
  -- because after this function returns the user can never sign in to deal with the rest.
  if p_delete_shared_data then
    for v_couple_id in
      select id from public.couples
      where partner_a_id = v_uid or partner_b_id = v_uid
    loop
      perform public.purge_couple_data(v_couple_id);
    end loop;
  end if;

  -- This user's own storage objects. When p_delete_shared_data is false these are the only
  -- files removed — shared content (memory photos, flight documents) stays for the other
  -- partner, same as an ordinary `leave_couple` already leaves it.
  -- avatars/{profileID}/..., drawing-pads/{coupleID}/{profileID}/... (see
  -- 20260901001000_private_avatars_drawing_pads.sql's RLS policies for the same path shape).
  perform set_config('storage.allow_delete_query', 'true', true);
  delete from storage.objects where bucket_id = 'avatars' and (storage.foldername(name))[1] = v_uid::text;
  delete from storage.objects where bucket_id = 'drawing-pads' and (storage.foldername(name))[2] = v_uid::text;

  -- Every push token revoked so a deleted account can never receive another notification.
  delete from public.device_push_tokens where profile_id = v_uid;
  delete from public.live_activity_push_tokens where profile_id = v_uid;

  -- Scrub this user's own identifying fields rather than deleting the row — see
  -- 20260901001500's header for why the row itself has to survive. Only ever this profile's own
  -- row (`where id = v_uid`) — never the partner's, including partner-facing fields like
  -- `partner_name`, which is this user's own nickname override, not the partner's own data.
  update public.profiles
  set first_name = 'Deleted User',
      avatar_path = null,
      partner_avatar_path = null,
      partner_name = null,
      home_place_id = null,
      partner_home_place_id = null,
      account_deleted_at = now()
  where id = v_uid;
end;
$$;

revoke all on function public.delete_own_account(boolean) from public;
grant execute on function public.delete_own_account(boolean) to authenticated;
