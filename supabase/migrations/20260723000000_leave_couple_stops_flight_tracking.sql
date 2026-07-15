-- `leave_couple` dissolved the couple but never touched its flights, so anything still
-- `tracking_enabled` at dissolution time stayed that way forever — `fetchCoupleState()` only
-- loads couples with status = 'active', so those flights become permanently unreachable
-- client-side, yet refresh-due-flights' cron query (`.eq("tracking_enabled", true)`, no couple-
-- status join) kept polling AeroAPI for them every 5 minutes regardless. Same bug class as
-- 20260712180000's game_sessions fix, applied to flights.
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

  update public.flights
  set tracking_enabled = false
  where couple_id = p_couple_id
    and tracking_enabled;

  return v_couple;
end;
$$;

-- One-time backfill: flights already orphaned by a couple that dissolved before this fix
-- existed (mirrors the game_sessions backfill in 20260712180000).
update public.flights f
set tracking_enabled = false
from public.couples c
where f.couple_id = c.id
  and c.status = 'dissolved'
  and f.tracking_enabled;
