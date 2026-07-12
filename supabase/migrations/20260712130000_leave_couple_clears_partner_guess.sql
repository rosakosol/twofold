-- `leave_couple` dissolved the couple but left the caller's personal "partner guess" fields on
-- their own profile row untouched (partner_name/partner_avatar_path/partner_home_place_id/
-- anniversary_date) — these are meant as a pre-pairing guess you can set before a real partner
-- joins (see profiles_update_self policy + BackendService's updatePartnerNickname/
-- uploadPartnerAvatar/updatePartnerHomeCityGuess/updateAnniversaryDate, all "always personal,
-- paired or not"). In practice, once actually paired, these fields end up holding the *real*
-- partner's actual name/photo/city — so after removing that partner, the old fields silently
-- kept showing their info everywhere (Settings' partner card, Home's same-city/anniversary
-- cards), making it look like removal hadn't worked at all. Clearing them here, atomically with
-- the dissolution itself, so "remove partner" actually starts the caller from a clean slate.

create or replace function public.leave_couple(p_couple_id uuid)
returns public.couples
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

  if v_couple.status = 'dissolved' then
    raise exception 'This couple has already been dissolved';
  end if;

  update public.couples
  set status = 'dissolved', dissolved_at = now(), dissolved_by = v_caller_id
  where id = p_couple_id
  returning * into v_couple;

  update public.profiles
  set partner_name = null, partner_avatar_path = null, partner_home_place_id = null, anniversary_date = null
  where id = v_caller_id;

  return v_couple;
end;
$$;

revoke all on function public.leave_couple(uuid) from public;
grant execute on function public.leave_couple(uuid) to authenticated;
