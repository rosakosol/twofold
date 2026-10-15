-- Two ways an account deletion did less than it says.
--
-- ---------------------------------------------------------------------------
-- 1. A deleted account's invites still worked
-- ---------------------------------------------------------------------------
--
-- `private.scrub_account` dissolves the active couple but left the account's pending
-- `invite_codes` and `connection_requests` alone. `redeem_invite_code` only refuses an inviter who
-- is already in an active couple — which a scrubbed one, by construction, is not — so anybody
-- holding the deleted person's invite link could still tap it, and `origin = 'link'` auto-accepts:
-- an active couple with an account nobody can sign in to, on whoever happened to have the link. A
-- pending request the deleted person had sent was likewise still there for the other side to
-- accept.
--
-- Invites are expired and pending requests declined, in the same call that scrubs the name. Both
-- statuses already exist and mean exactly this; nothing reads either as an event to notify about.
--
-- ---------------------------------------------------------------------------
-- 2. Dormant closure was a copy of the scrub, and the copy stopped being updated
-- ---------------------------------------------------------------------------
--
-- `close_dormant_account` (20261029000100) is documented as "deliberately the same shape as
-- `delete_own_account`" and was written as a copy of its body. Three later changes went into
-- `private.scrub_account` only:
--
--   * 20261110000000 queues the account's R2 objects before nulling the columns that name them.
--     The dormant copy still nulls `avatar_path` / `partner_avatar_path` without queuing them, so
--     a dormant-closed account's photos stay in R2 permanently with nothing left recording that
--     they exist — the exact leak that migration was written to close.
--   * 20261110000800 clears the leaver's name from a partner's lapse notice.
--   * 20261111001100 deletes solo game sessions.
--
-- The dormant closure now calls the scrub, keeping only its own already-closed guard. There is one
-- definition of "what deleting an account removes", and the next change to it reaches both.

create or replace function private.scrub_account(p_profile_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_couple_id uuid;
begin
  perform private.enqueue_object_deletions(
    array(select private.profile_object_keys(p_profile_id))
  );

  -- Dissolve any couple this profile is still actively part of, so the remaining partner gets the
  -- normal "partner left" experience rather than their partner silently disappearing. The
  -- trg_couples_archive_clock trigger stamps each one with its deletion date.
  --
  -- Deliberately still the plain UPDATE the original used, not private.dissolve_couple: a deletion
  -- is not a disconnection. Arming the "your subscription lapsed because they left" notice would
  -- name a person whose account no longer exists, and abandoning their games and flights is
  -- already handled by everything downstream of the profile being scrubbed.
  for v_couple_id in
    select id from public.couples
    where (partner_a_id = p_profile_id or partner_b_id = p_profile_id) and status = 'active'
  loop
    update public.couples
    set status = 'dissolved', dissolved_at = now(), dissolved_by = p_profile_id
    where id = v_couple_id;
  end loop;

  -- Nothing this account started can be finished by somebody else. See the header: an unexpired
  -- invite link would otherwise pair its holder with an account nobody can sign in to.
  update public.invite_codes
  set status = 'expired'
  where inviter_id = p_profile_id and status = 'pending';

  update public.connection_requests
  set status = 'declined', responded_at = now()
  where status = 'pending'
    and (inviter_id = p_profile_id or requester_id = p_profile_id);

  -- Solo sessions only — see 20261111001100. Cascades to game_responses and game_session_rounds.
  delete from public.game_sessions
  where couple_id is null and initiator_id = p_profile_id;

  perform set_config('storage.allow_delete_query', 'true', true);
  delete from storage.objects where bucket_id = 'avatars' and (storage.foldername(name))[1] = p_profile_id::text;
  delete from storage.objects where bucket_id = 'drawing-pads' and (storage.foldername(name))[2] = p_profile_id::text;

  delete from public.device_push_tokens where profile_id = p_profile_id;
  delete from public.live_activity_push_tokens where profile_id = p_profile_id;

  -- Anywhere this person's name was copied onto somebody else's row. The notice it belongs to is
  -- retired at the same time: it exists to explain a lapse caused by a person, and once that
  -- person is gone there is no longer anybody to name.
  update public.profiles
  set partner_subscription_lapse_partner_name = null,
      partner_subscription_lapse_shown = true
  where partner_subscription_lapse_partner_name is not null
    and exists (
      select 1 from public.couples c
      where (c.partner_a_id = p_profile_id and c.partner_b_id = profiles.id)
         or (c.partner_b_id = p_profile_id and c.partner_a_id = profiles.id)
    );

  update public.profiles
  set first_name = 'Deleted User',
      avatar_path = null,
      partner_avatar_path = null,
      partner_name = null,
      home_place_id = null,
      partner_home_place_id = null,
      account_deleted_at = now()
  where id = p_profile_id;
end;
$$;

revoke all on function private.scrub_account(uuid) from public, anon, authenticated;

create or replace function public.close_dormant_account(p_profile_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  if p_profile_id is null then
    raise exception 'close_dormant_account requires a profile id';
  end if;

  -- Its own guard, kept: re-running on an already-closed account is a no-op, which is what lets a
  -- half-failed cron run simply be repeated. `scrub_account` itself would re-stamp the deletion.
  if not exists (
    select 1 from public.profiles
    where id = p_profile_id and account_deleted_at is null
  ) then
    return;
  end if;

  perform private.scrub_account(p_profile_id);
end;
$$;

revoke all on function public.close_dormant_account(uuid) from public, anon, authenticated;
grant execute on function public.close_dormant_account(uuid) to service_role;
