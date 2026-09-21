-- A third party's first name survives a scrub, on a row that reads "Deleted User".
--
-- `leave_couple` copies the leaver's own `first_name` onto the *remaining* partner's profile, into
-- `partner_subscription_lapse_partner_name`, so the app can say who left when it explains why the
-- subscription lapsed (20260906000100). That is the right design for the notice.
--
-- Only `partner_subscription_lapse_shown` is ever flipped afterwards — nothing anywhere clears the
-- name — and `private.scrub_account` nulls `partner_name` and `partner_avatar_path` but not this
-- one. So when the person who left later deletes their account, their first name stays on somebody
-- else's row indefinitely, against the privacy policy's "your name, your photo, your partner
-- nickname and partner photo are erased".
--
-- Cleared on the remaining partner's rows, not on the leaver's own: the column is a copy held
-- *about* them, which is the whole reason it outlived them.
--
-- Body otherwise unchanged from 20261110000000, which is itself 20261109000900's with the R2
-- enqueue at the top.

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
