-- Self-serve account deletion. `delete_own_account()` does careful, scoped cleanup — it does
-- NOT hard-delete the `auth.users`/`profiles` row itself. `profiles.id references auth.users
-- (id) on delete cascade` combined with `couples.partner_a_id/partner_b_id references profiles
-- (id) on delete cascade` means a plain `auth.admin.deleteUser` would cascade-delete the ENTIRE
-- couples row the instant either partner's account is removed — and every trip/memory/flight/
-- game inside it along with it, including a long-dissolved couple's shared history the *other*,
-- still-active partner never asked to lose just because their ex deleted their own account.
--
-- Instead this function scrubs only the deleting user's own identifying fields and their own
-- storage objects, leaving the profile row (and any couple it's linked to) intact for
-- referential integrity — exactly how `leave_couple` already treats shared history as belonging
-- to the relationship, not solely to one party. The actual `auth.users` row is then
-- soft-deleted (`deleted_at` set, sign-in permanently disabled, row otherwise left alone so the
-- FK above never fires) from the `delete-account` Edge Function, the only context with the
-- service-role access that requires.

alter table public.profiles add column account_deleted_at timestamptz;

create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_couple record;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  -- Dissolve any couple this profile is still actively part of first — the same status flip
  -- `leave_couple` performs — so the remaining partner gets the normal "partner left"
  -- experience instead of their partner's name/photo just silently disappearing with no signal
  -- anything happened.
  for v_couple in
    select id from public.couples
    where (partner_a_id = v_uid or partner_b_id = v_uid) and status = 'active'
  loop
    update public.couples
    set status = 'dissolved', dissolved_at = now(), dissolved_by = v_uid
    where id = v_couple.id;
  end loop;

  -- This user's own storage objects only — shared content (memory photos, flight documents)
  -- stays untouched, same as an ordinary `leave_couple` already leaves it for the other partner.
  -- avatars/{profileID}/..., drawing-pads/{coupleID}/{profileID}/... (see
  -- 20260901001000_private_avatars_drawing_pads.sql's RLS policies for the same path shape).
  perform set_config('storage.allow_delete_query', 'true', true);
  delete from storage.objects where bucket_id = 'avatars' and (storage.foldername(name))[1] = v_uid::text;
  delete from storage.objects where bucket_id = 'drawing-pads' and (storage.foldername(name))[2] = v_uid::text;

  -- Every push token revoked so a deleted account can never receive another notification.
  delete from public.device_push_tokens where profile_id = v_uid;
  delete from public.live_activity_push_tokens where profile_id = v_uid;

  -- Scrub this user's own identifying fields rather than deleting the row — see file header
  -- comment. Only ever this profile's own row (`where id = v_uid`) — never touches the
  -- partner's own profile fields, even the partner-facing ones like `partner_name`, which is
  -- this user's *own* nickname override for their partner, not the partner's own data.
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

revoke all on function public.delete_own_account() from public;
grant execute on function public.delete_own_account() to authenticated;
