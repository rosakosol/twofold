-- ---------------------------------------------------------------------------
-- Deleting a shared archive is only ever the clock running out
-- ---------------------------------------------------------------------------
--
-- 20261003000000 made a shared purge need both partners to agree, because either of them could
-- destroy the other's copy alone. 20261004000000 then gave every archive a 90-day life, deleted
-- automatically, without needing anyone's agreement.
--
-- With the second of those in place the first is no longer the mechanism, it is a second mechanism
-- — and a worse one to reason about. Two ways to delete the same thing, one of them a negotiation
-- with four states on screen, when the answer to "when does this go?" should be a date.
--
-- So: the timer is the only way a shared archive is deleted. What is left of
-- `couple_archive_preferences` is `hidden_at`, which was always a different thing — one person's
-- own view, unilateral by design, and destructive of nothing.
--
-- The protection that mattered is unchanged and is now simply structural: there is no call any
-- client can make that destroys a couple's shared data. Not a policy that says no — no such
-- function.
--
-- What someone loses is the ability to have it gone sooner than 90 days by mutual agreement. That
-- is a deliberate trade for one comprehensible rule, and the export added alongside this means
-- nobody has to keep the archive to keep what was in it.

drop function if exists public.request_couple_purge(uuid);
drop function if exists public.withdraw_couple_purge(uuid);

alter table public.couple_archive_preferences
  drop column if exists purge_requested_at;

comment on table public.couple_archive_preferences is
  'Whether a person has hidden a past relationship from their own Archived Data list. Nothing here '
  'deletes anything: a shared archive goes when its 90 days are up, and by no other route.';

-- Now only ever about one person's own view.
--
-- Dropped first, not replaced: `create or replace` cannot narrow a `returns table` signature —
-- Postgres treats the column list as part of the return type and refuses with 42P13.
drop function if exists public.couple_archive_state(uuid);

create function public.couple_archive_state(p_couple_id uuid)
returns table (hidden boolean)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  if not public.is_couple_member(p_couple_id) then
    raise exception 'You are not a member of this couple' using errcode = '42501';
  end if;

  return query
  select coalesce((
    select p.hidden_at is not null
    from public.couple_archive_preferences p
    where p.couple_id = p_couple_id and p.profile_id = v_me
  ), false);
end;
$$;

revoke all on function public.couple_archive_state(uuid) from public;
grant execute on function public.couple_archive_state(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Account deletion stops offering to take the shared data with it
-- ---------------------------------------------------------------------------
--
-- `p_delete_shared_data` was the last route to an early purge. It is kept in the signature so
-- builds already installed keep working, and it now does nothing: dissolving starts the same
-- 90-day clock as unpairing, and the archive goes when that runs out.
--
-- Right to erasure is unaffected. Everything that is actually this person's own — their profile
-- fields, avatar, drawings, push tokens — is still deleted here and immediately. What they no
-- longer carry off with them is the other person's half of a shared history.
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

  -- Dissolve any couple this profile is still actively part of, so the remaining partner gets the
  -- normal "partner left" experience rather than their partner silently disappearing. The
  -- trg_couples_archive_clock trigger stamps each one with its deletion date.
  for v_couple_id in
    select id from public.couples
    where (partner_a_id = v_uid or partner_b_id = v_uid) and status = 'active'
  loop
    update public.couples
    set status = 'dissolved', dissolved_at = now(), dissolved_by = v_uid
    where id = v_couple_id;
  end loop;

  -- This user's own storage objects. Shared content stays until its archive expires.
  perform set_config('storage.allow_delete_query', 'true', true);
  delete from storage.objects where bucket_id = 'avatars' and (storage.foldername(name))[1] = v_uid::text;
  delete from storage.objects where bucket_id = 'drawing-pads' and (storage.foldername(name))[2] = v_uid::text;

  delete from public.device_push_tokens where profile_id = v_uid;
  delete from public.live_activity_push_tokens where profile_id = v_uid;

  -- Scrub this user's own identifying fields rather than deleting the row — see 20260901001500's
  -- header for why the row itself has to survive. Only ever this profile's own row.
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
