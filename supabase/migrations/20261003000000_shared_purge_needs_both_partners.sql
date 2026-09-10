-- ---------------------------------------------------------------------------
-- Deleting shared data takes both partners
-- ---------------------------------------------------------------------------
--
-- Everything a couple made together — trips, memories and their photos, flights, game history —
-- belongs to the two of them. Until now either one of them could destroy all of it, alone, for
-- both, with no warning to the other and nothing to recover:
--
--   * `delete_dissolved_couple_data` checks only that you are *a* member of a dissolved couple.
--     One tap in Settings -> Archived Data and the other person's copy of a shared decade is gone.
--   * `delete_own_account(p_delete_shared_data => true)` loops over every couple the caller has
--     ever been in and purges each one outright.
--
-- Both are irreversible: `purge_couple_data` deletes the storage objects by prefix and then the
-- couples row, and everything else cascades. There is no tombstone and nothing to restore from.
--
-- The rule this migration puts in place: a shared purge needs both partners to ask for it, and
-- anyone who simply doesn't want to see an old relationship any more gets a per-person hide that
-- destroys nothing.
--
-- Those are two genuinely different wishes that the single "Delete Permanently" button was
-- conflating. Almost everyone reaching for it wants the first — the archive out of their sight —
-- and gets handed the second, which also reaches into someone else's account.
--
-- ---------------------------------------------------------------------------
-- The exception, and why it is not a loophole
-- ---------------------------------------------------------------------------
--
-- If the other partner has deleted their account, one request is enough. Otherwise a purge would
-- need consent from someone who no longer exists, and the data would be undeletable forever by the
-- only person left who can see it.
--
-- Checked as `account_deleted_at is not null`, NOT as the profiles row being missing. Deleting an
-- account does not delete that row — `delete_own_account` scrubs the identifying fields and stamps
-- `account_deleted_at`, deliberately, so that shared content keeps a valid foreign key (see
-- 20260901001500's header). An `exists (select 1 from profiles ...)` test would therefore call
-- every deleted partner present, and the exception would never fire for the case it exists for.
-- Neither field is client-writable, so this is not something a caller can influence.

create table public.couple_archive_preferences (
  couple_id uuid not null references public.couples (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  -- Hidden from this person's Archived Data list. Non-destructive and unilateral by design: it is
  -- entirely about one person's own view, so it needs nobody else's agreement.
  hidden_at timestamptz,
  -- This person has asked for the shared data to be destroyed. Purge happens when both have.
  purge_requested_at timestamptz,
  primary key (couple_id, profile_id)
);

alter table public.couple_archive_preferences enable row level security;

-- Readable by both partners, deliberately. Someone who has asked for a purge and is waiting needs
-- to see that they are waiting, and the partner needs to see that they have been asked — a request
-- the other person cannot see is not a request, it is a trap that fires when they happen to tap
-- the same button.
create policy "couple_archive_preferences_select_members" on public.couple_archive_preferences
  for select using (public.is_couple_member(couple_id));

-- No insert/update/delete policy: written only through the functions below, which is what keeps
-- one partner from recording the other's consent.

comment on table public.couple_archive_preferences is
  'Per-person state for a dissolved couple''s archive: whether they have hidden it from their own '
  'view, and whether they have asked for the shared data to be destroyed. A purge needs both.';

-- ---------------------------------------------------------------------------
-- Hiding: one person's own view, nobody else's business
-- ---------------------------------------------------------------------------

create or replace function public.set_couple_archive_hidden(p_couple_id uuid, p_hidden boolean)
returns void
language plpgsql
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

  insert into public.couple_archive_preferences (couple_id, profile_id, hidden_at)
  values (p_couple_id, v_me, case when p_hidden then now() else null end)
  on conflict (couple_id, profile_id)
  do update set hidden_at = case when p_hidden then now() else null end;
end;
$$;

revoke all on function public.set_couple_archive_hidden(uuid, boolean) from public;
grant execute on function public.set_couple_archive_hidden(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- Purging: both, or one if the other no longer exists
-- ---------------------------------------------------------------------------

-- Records the caller's request and purges if that completes the pair. Returns what happened:
-- 'purged' or 'awaiting_partner'.
create or replace function public.request_couple_purge(p_couple_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_couple public.couples;
  v_partner_id uuid;
  v_partner_exists boolean;
  v_partner_requested boolean;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  -- Locked for the duration: two partners tapping at the same moment must not both read "the
  -- other hasn't asked yet" and both come away thinking they are waiting.
  select * into v_couple from public.couples where id = p_couple_id for update;

  if not found then
    raise exception 'Couple not found';
  end if;

  if v_couple.partner_a_id <> v_me and v_couple.partner_b_id <> v_me then
    raise exception 'You are not a member of this couple' using errcode = '42501';
  end if;

  -- Dissolving stays the deliberate, separate first step, so a permanent delete can never be
  -- triggered on live data. Unchanged from the function this replaces.
  if v_couple.status <> 'dissolved' then
    raise exception 'Only a dissolved couple''s data can be permanently deleted';
  end if;

  v_partner_id := case when v_couple.partner_a_id = v_me then v_couple.partner_b_id else v_couple.partner_a_id end;

  insert into public.couple_archive_preferences (couple_id, profile_id, purge_requested_at)
  values (p_couple_id, v_me, now())
  on conflict (couple_id, profile_id)
  do update set purge_requested_at = coalesce(public.couple_archive_preferences.purge_requested_at, now());

  select exists (
    select 1 from public.profiles where id = v_partner_id and account_deleted_at is null
  ) into v_partner_exists;

  select exists (
    select 1 from public.couple_archive_preferences
    where couple_id = p_couple_id and profile_id = v_partner_id and purge_requested_at is not null
  ) into v_partner_requested;

  -- The absent-partner case is decided by the profile genuinely not being there, never by
  -- anything a caller can influence.
  if v_partner_requested or not v_partner_exists then
    perform public.purge_couple_data(p_couple_id);
    return 'purged';
  end if;

  return 'awaiting_partner';
end;
$$;

revoke all on function public.request_couple_purge(uuid) from public;
grant execute on function public.request_couple_purge(uuid) to authenticated;

-- Takes back a request that hasn't been met yet. Nothing to undo once a purge has happened —
-- there is no couple row left to hold the preference.
create or replace function public.withdraw_couple_purge(p_couple_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  update public.couple_archive_preferences
  set purge_requested_at = null
  where couple_id = p_couple_id and profile_id = v_me;
end;
$$;

revoke all on function public.withdraw_couple_purge(uuid) from public;
grant execute on function public.withdraw_couple_purge(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- What the archive screen needs to know
-- ---------------------------------------------------------------------------

create or replace function public.couple_archive_state(p_couple_id uuid)
returns table (
  hidden boolean,
  i_requested_purge boolean,
  partner_requested_purge boolean,
  partner_exists boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_couple public.couples;
  v_partner_id uuid;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select * into v_couple from public.couples where id = p_couple_id;

  if not found or (v_couple.partner_a_id <> v_me and v_couple.partner_b_id <> v_me) then
    raise exception 'You are not a member of this couple' using errcode = '42501';
  end if;

  v_partner_id := case when v_couple.partner_a_id = v_me then v_couple.partner_b_id else v_couple.partner_a_id end;

  return query
  select
    coalesce((select p.hidden_at is not null from public.couple_archive_preferences p
              where p.couple_id = p_couple_id and p.profile_id = v_me), false),
    coalesce((select p.purge_requested_at is not null from public.couple_archive_preferences p
              where p.couple_id = p_couple_id and p.profile_id = v_me), false),
    coalesce((select p.purge_requested_at is not null from public.couple_archive_preferences p
              where p.couple_id = p_couple_id and p.profile_id = v_partner_id), false),
    exists (select 1 from public.profiles where id = v_partner_id and account_deleted_at is null);
end;
$$;

revoke all on function public.couple_archive_state(uuid) from public;
grant execute on function public.couple_archive_state(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- The old unilateral delete
-- ---------------------------------------------------------------------------
--
-- Made to fail rather than quietly redirected. A build still calling this would show its user a
-- success and leave the data standing, which is a worse lie than an error — and the alternative,
-- letting it through, is the exact behaviour this migration exists to remove. Failing loudly is
-- the only option that neither destroys the partner's data nor claims to have.
create or replace function public.delete_dissolved_couple_data(p_couple_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'Deleting shared data now needs both partners to agree. Update Twofold to continue.'
    using errcode = '42501';
end;
$$;

-- ---------------------------------------------------------------------------
-- Account deletion stops being a way to purge someone else's copy
-- ---------------------------------------------------------------------------
--
-- `delete_own_account(p_delete_shared_data => true)` purged every couple the caller had ever been
-- in, outright. That is the same unilateral destruction as the button above, reached by a
-- different route, and it hit harder: every archive at once, with the partner never asked.
--
-- Now it records the caller's request against each couple and purges only where that completes the
-- pair — the partner has already asked, or the partner's account is already deleted. Where the
-- partner is still there and has not asked, their copy stands, which is the whole point.
--
-- Right to erasure is untouched: everything below this that is actually the caller's own — their
-- profile fields, avatar, drawings, push tokens — is still deleted unconditionally, exactly as
-- before. What they no longer get is the power to erase someone else's half of a shared history.
--
-- Their request row survives their own deletion (the profiles row survives, so the foreign key
-- holds), so a partner who later asks completes the pair and the purge happens then.
create or replace function public.delete_own_account(p_delete_shared_data boolean default false)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_couple_id uuid;
  v_partner_id uuid;
  v_couple public.couples;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  -- Dissolve any couple this profile is still actively part of first — the same status flip
  -- `leave_couple` performs — so the remaining partner gets the normal "partner left"
  -- experience instead of their partner's name/photo silently disappearing with no signal
  -- anything happened.
  for v_couple_id in
    select id from public.couples
    where (partner_a_id = v_uid or partner_b_id = v_uid) and status = 'active'
  loop
    update public.couples
    set status = 'dissolved', dissolved_at = now(), dissolved_by = v_uid
    where id = v_couple_id;
  end loop;

  if p_delete_shared_data then
    for v_couple_id in
      select id from public.couples
      where partner_a_id = v_uid or partner_b_id = v_uid
    loop
      select * into v_couple from public.couples where id = v_couple_id;
      v_partner_id := case
        when v_couple.partner_a_id = v_uid then v_couple.partner_b_id
        else v_couple.partner_a_id
      end;

      insert into public.couple_archive_preferences (couple_id, profile_id, purge_requested_at)
      values (v_couple_id, v_uid, now())
      on conflict (couple_id, profile_id)
      do update set purge_requested_at = coalesce(public.couple_archive_preferences.purge_requested_at, now());

      if exists (
        select 1 from public.couple_archive_preferences
        where couple_id = v_couple_id and profile_id = v_partner_id and purge_requested_at is not null
      ) or not exists (
        select 1 from public.profiles where id = v_partner_id and account_deleted_at is null
      ) then
        perform public.purge_couple_data(v_couple_id);
      end if;
    end loop;
  end if;

  -- This user's own storage objects. Shared content (memory photos, flight documents) stays for
  -- the other partner unless the loop above purged the couple.
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
