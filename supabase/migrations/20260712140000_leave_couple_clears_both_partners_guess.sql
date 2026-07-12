-- The previous fix (20260712130000) only cleared the *caller's* own partner-guess fields —
-- whichever partner didn't initiate the removal would keep their own partner_name/
-- partner_avatar_path/partner_home_place_id/anniversary_date pointing at the person who just
-- left, hitting the exact same "looks like nothing happened" confusion on their side once they
-- open the app. Clears both partners' guess fields now, atomically with the dissolution.

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
  where id in (v_couple.partner_a_id, v_couple.partner_b_id);

  return v_couple;
end;
$$;

revoke all on function public.leave_couple(uuid) from public;
grant execute on function public.leave_couple(uuid) to authenticated;
