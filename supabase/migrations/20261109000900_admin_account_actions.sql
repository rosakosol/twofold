-- ---------------------------------------------------------------------------
-- Doing something about an account, on its owner's behalf
-- ---------------------------------------------------------------------------
--
-- Support can now find an account (20261109000800). This is the half that acts on one: dissolving
-- a couple and scrubbing an account, for the two requests that actually arrive — "disconnect me
-- from my partner" and "delete my account" — from somebody who cannot do it themselves because
-- they cannot sign in, or because the app is refusing, or because they asked by email and that is
-- the only channel they have.
--
-- ---------------------------------------------------------------------------
-- Extracted, not copied
-- ---------------------------------------------------------------------------
--
-- `leave_couple` and `delete_own_account` each do real work: dissolving a couple abandons games,
-- stops flight tracking, clears four partner fields on both profiles, and arms the "your
-- subscription lapsed because they left" notice on exactly the right one of them. Writing an admin
-- variant by copying that body would create two implementations of what dissolving means, and they
-- would drift — which here means the remaining partner gets a different experience depending on
-- which button was pressed. That is not a difference anybody would notice until it mattered.
--
-- So the bodies move into `private.dissolve_couple` and `private.scrub_account`, and the existing
-- public functions become what they always were underneath: an authorisation check in front of a
-- piece of work. The admin entry points are a different check in front of the same work.
--
-- ---------------------------------------------------------------------------
-- On whose behalf
-- ---------------------------------------------------------------------------
--
-- `dissolve_couple` takes the partner it is acting for, not the admin. That matters because the
-- result is not symmetric: `couples.dissolved_by` records who left, and the subscription-lapse
-- notice is armed on the partner who did NOT leave and was relying on the leaver's subscription.
-- An admin is not a member of the couple and cannot be either of those people.
--
-- So an admin disconnecting somebody performs it as that person: `dissolved_by` is the partner who
-- asked, exactly as if they had pressed the button themselves, and every downstream consequence is
-- the one the app already produces. Who actually did it is recorded in `admin_audit_log`, which is
-- where that fact belongs.

-- ---------------------------------------------------------------------------
-- The work: dissolving a couple
-- ---------------------------------------------------------------------------

create or replace function private.dissolve_couple(p_couple_id uuid, p_on_behalf_of uuid)
returns public.couples
language plpgsql
security definer
set search_path = public
as $$
declare
  v_couple public.couples;
  v_remaining_id uuid;
  v_leaver_paid boolean;
  v_remaining_paid boolean;
  v_leaver_first_name text;
begin
  select * into v_couple from public.couples where id = p_couple_id for update;

  if not found then
    raise exception 'Couple not found';
  end if;

  if v_couple.partner_a_id <> p_on_behalf_of and v_couple.partner_b_id <> p_on_behalf_of then
    raise exception 'That profile is not a member of this couple';
  end if;

  if v_couple.status = 'dissolved' then
    raise exception 'This couple has already been dissolved';
  end if;

  v_remaining_id := case when v_couple.partner_a_id = p_on_behalf_of then v_couple.partner_b_id else v_couple.partner_a_id end;

  select subscription_active, first_name into v_leaver_paid, v_leaver_first_name
  from public.profiles where id = p_on_behalf_of;
  select subscription_active into v_remaining_paid
  from public.profiles where id = v_remaining_id;

  update public.couples
  set status = 'dissolved', dissolved_at = now(), dissolved_by = p_on_behalf_of
  where id = p_couple_id
  returning * into v_couple;

  update public.profiles
  set partner_name = null, partner_avatar_path = null, partner_home_place_id = null, anniversary_date = null,
      partner_subscription_lapse_partner_name = case
        when id = v_remaining_id and coalesce(v_leaver_paid, false) and not coalesce(v_remaining_paid, false)
          then coalesce(v_leaver_first_name, 'Your partner')
        else partner_subscription_lapse_partner_name
      end,
      partner_subscription_lapse_shown = case
        when id = v_remaining_id and coalesce(v_leaver_paid, false) and not coalesce(v_remaining_paid, false)
          then false
        else partner_subscription_lapse_shown
      end
  where id in (v_couple.partner_a_id, v_couple.partner_b_id);

  update public.game_sessions
  set status = 'abandoned', updated_at = now()
  where couple_id = p_couple_id
    and status in ('draft', 'active', 'waiting_for_partner');

  update public.flights
  set tracking_enabled = false
  where couple_id = p_couple_id
    and tracking_enabled;

  return v_couple;
end;
$$;

revoke all on function private.dissolve_couple(uuid, uuid) from public, anon, authenticated;

-- Now an authorisation check in front of that work, which is all it ever was. The membership test
-- is kept here as well as inside: `dissolve_couple` raises a message naming a profile, which is
-- right for an admin tool and wrong for the app, where the caller IS the profile.
create or replace function public.leave_couple(p_couple_id uuid)
returns public.couples
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id uuid := auth.uid();
  v_couple public.couples;
begin
  if v_caller_id is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_couple from public.couples where id = p_couple_id;
  if not found then
    raise exception 'Couple not found';
  end if;
  if v_couple.partner_a_id <> v_caller_id and v_couple.partner_b_id <> v_caller_id then
    raise exception 'You are not a member of this couple';
  end if;

  return private.dissolve_couple(p_couple_id, v_caller_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- The work: scrubbing an account
-- ---------------------------------------------------------------------------
--
-- Scrubs identifying fields rather than deleting the row, and the reason is in 20260901001500's
-- header: the FK cascade from `profiles` to `couples` would take the OTHER partner's shared
-- history with it. The row survives so their side does.

create or replace function private.scrub_account(p_profile_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_couple_id uuid;
begin
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

create or replace function public.delete_own_account(p_delete_shared_data boolean default false)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  -- `p_delete_shared_data` has been ignored since 20261005000000 made the 90-day archive clock the
  -- only route by which shared data is ever deleted. Kept in the signature because older installed
  -- builds still send it.
  perform private.scrub_account(v_uid);
end;
$$;

-- ---------------------------------------------------------------------------
-- The admin entry points
-- ---------------------------------------------------------------------------
--
-- `p_reason` is NOT optional on either, unlike on `admin_account_detail`. Requiring a typed
-- justification before you may look at the account somebody just emailed about is friction against
-- the normal case. Requiring one before you dissolve their relationship or delete their account is
-- the point: the row in the audit log is the only thing that will explain this in two years, and
-- an unexplained destructive action found later is indistinguishable from a mistake.

create or replace function public.admin_dissolve_couple(
  p_couple_id uuid,
  p_on_behalf_of uuid,
  p_reason text
)
returns public.couples
language plpgsql
security definer
set search_path = private, public
as $$
declare
  v_couple public.couples;
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'a reason is required' using errcode = '22023';
  end if;

  v_couple := private.dissolve_couple(p_couple_id, p_on_behalf_of);

  perform private.record_admin_action(
    'couple.dissolve', p_on_behalf_of, p_reason,
    jsonb_build_object(
      'couple_id', p_couple_id,
      'partner_id', case when v_couple.partner_a_id = p_on_behalf_of
        then v_couple.partner_b_id else v_couple.partner_a_id end
    )
  );

  return v_couple;
end;
$$;

-- Scrubbing only. The rest of a deletion — cancelling a web subscription first, and soft-deleting
-- the auth.users row — needs the service role and a Stripe call, and lives in the `admin-actions`
-- edge function. This is the database half, exposed separately so that half is testable on its own.
create or replace function public.admin_scrub_account(p_profile_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = private, public
as $$
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'a reason is required' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = p_profile_id) then
    raise exception 'no such account';
  end if;

  perform private.scrub_account(p_profile_id);
  perform private.record_admin_action('account.scrub', p_profile_id, p_reason, null);
end;
$$;

-- ---------------------------------------------------------------------------
-- Recording an action taken from an edge function
-- ---------------------------------------------------------------------------
--
-- `private.record_admin_action` reads `auth.uid()`, which is null under the service role — so the
-- edge function, which verifies the caller's JWT itself and then acts with the service role, has
-- to pass the actor explicitly. Granted to `service_role` alone: an actor id a client could choose
-- is an audit log a client could forge, and a log that can be forged is worse than none, because
-- it is trusted.

create or replace function public.admin_record_action(
  p_actor uuid,
  p_action text,
  p_subject uuid default null,
  p_reason text default null,
  p_details jsonb default null
)
returns void
language sql
security definer
set search_path = private, public
as $$
  insert into private.admin_audit_log (actor_id, action, subject_profile_id, reason, details)
  values (p_actor, p_action, p_subject, p_reason, p_details);
$$;

revoke execute on function public.admin_record_action(uuid, text, uuid, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.admin_record_action(uuid, text, uuid, text, jsonb) to service_role;

revoke execute on function public.admin_dissolve_couple(uuid, uuid, text) from anon;
revoke execute on function public.admin_scrub_account(uuid, text) from anon;
grant execute on function public.admin_dissolve_couple(uuid, uuid, text) to authenticated;
grant execute on function public.admin_scrub_account(uuid, text) to authenticated;
