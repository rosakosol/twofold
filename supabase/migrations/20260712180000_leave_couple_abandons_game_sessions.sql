-- `leave_couple` dissolved the couple but never touched in-flight `game_sessions`, so a
-- session still `active`/`waiting_for_partner` at dissolution time stayed that way forever.
-- `game_sessions_select_members` scopes by couple *membership*, not couple *status*, so the
-- client's resume logic (`GameEntryView.determinePhase()`) kept finding it and routing back
-- into play — which then failed on submit, since `game_responses_insert_own_active` correctly
-- requires the couple to still be active. Dissolution now abandons those sessions atomically,
-- so they drop out of resumability instead of dead-ending on the next answer.
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

  update public.game_sessions
  set status = 'abandoned', updated_at = now()
  where couple_id = p_couple_id
    and status in ('draft', 'active', 'waiting_for_partner');

  return v_couple;
end;
$$;

-- One-time backfill: sessions already orphaned by a couple that dissolved before this fix
-- existed (its game_sessions rows never got the abandon transition retroactively).
update public.game_sessions gs
set status = 'abandoned', updated_at = now()
from public.couples c
where gs.couple_id = c.id
  and c.status = 'dissolved'
  and gs.status in ('draft', 'active', 'waiting_for_partner');
