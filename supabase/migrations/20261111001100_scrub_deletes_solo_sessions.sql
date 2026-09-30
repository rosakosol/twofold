-- A solo player's own games outlived their account.
--
-- `private.scrub_account` clears the identifying columns on a profile and leaves the row in place,
-- which is right — the FK web makes a hard delete impossible (20260901001500). Everything keyed to
-- a couple then goes on the 90-day archive clock, and everything keyed to storage is deleted or
-- enqueued outright. Solo game sessions fell between the two.
--
-- 20260901001700 made `game_sessions.couple_id` nullable so an unpaired person can play Trivia
-- Battle, This or That and Deep Conversations on their own, with the row owned by `initiator_id`.
-- Nothing in the scrub touched `game_sessions`, and a solo session has no couple to cascade from —
-- so those rows, and every answer in them, survived a deletion attached to a profile now reading
-- "Deleted User". De-identified, but kept, and kept forever: no timer reaches them either.
--
-- That is not what somebody deleting their account is asking for. Their solo games are theirs alone
-- — there is no second person whose history this also is, which is the entire reason shared data
-- gets a 90-day archive instead of being deleted. With nobody else to consider, "delete my account"
-- means delete it.
--
-- `game_responses` and `game_session_rounds` both reference `game_sessions` with `on delete
-- cascade`, so one statement clears all three.
--
-- Scoped to `couple_id is null`. A session inside a couple is shared history — the partner played
-- it too, and it belongs to the archive clock along with the trips and memories. Deleting those
-- here would destroy the other person's copy, which 20261005000000 made sure nothing can do.
--
-- Body otherwise unchanged from 20261110000800.

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

  -- Solo sessions only — see the header. Cascades to game_responses and game_session_rounds.
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
