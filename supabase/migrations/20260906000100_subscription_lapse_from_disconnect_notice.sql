-- A non-paying partner whose ex-partner (the one actually covering the couple's subscription)
-- disconnects currently just lands on the generic "resubscribe" paywall with zero context — by
-- the time they next sign in, leave_couple has already nulled partner_name/partner_avatar_path
-- for both profiles, so there's no client-side way left to say *who* left or *why* access
-- disappeared. Captured here, server-side, at the exact moment of dissolution instead, since
-- that's the only point the name is still known.
--
-- Only armed when the leaver was actually paying and the remaining partner wasn't — if the
-- remaining partner has their own active subscription, nothing lapses for them and this notice
-- would be pointless/wrong.
--
-- `partner_subscription_lapse_shown` defaults to `true` ("nothing pending") so this never
-- retroactively fires for every couple that already dissolved before this migration — only a
-- genuinely new qualifying dissolution (see leave_couple below) ever sets it to `false`.
-- Deliberately re-armable (unlike partner_connected_celebration_shown, which never resets): if
-- this person later connects with someone new and that relationship also ends with them as the
-- non-payer, leave_couple sets it again on its own next run.
alter table public.profiles
  add column partner_subscription_lapse_partner_name text,
  add column partner_subscription_lapse_shown boolean not null default true;

create or replace function public.leave_couple(p_couple_id uuid)
returns public.couples
language plpgsql
security definer
set search_path = public
as $$
declare
  v_couple public.couples;
  v_caller_id uuid := auth.uid();
  v_remaining_id uuid;
  v_caller_paid boolean;
  v_remaining_paid boolean;
  v_caller_first_name text;
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

  v_remaining_id := case when v_couple.partner_a_id = v_caller_id then v_couple.partner_b_id else v_couple.partner_a_id end;

  select subscription_active, first_name into v_caller_paid, v_caller_first_name
  from public.profiles where id = v_caller_id;
  select subscription_active into v_remaining_paid
  from public.profiles where id = v_remaining_id;

  update public.couples
  set status = 'dissolved', dissolved_at = now(), dissolved_by = v_caller_id
  where id = p_couple_id
  returning * into v_couple;

  update public.profiles
  set partner_name = null, partner_avatar_path = null, partner_home_place_id = null, anniversary_date = null,
      partner_subscription_lapse_partner_name = case
        when id = v_remaining_id and coalesce(v_caller_paid, false) and not coalesce(v_remaining_paid, false)
          then coalesce(v_caller_first_name, 'Your partner')
        else partner_subscription_lapse_partner_name
      end,
      partner_subscription_lapse_shown = case
        when id = v_remaining_id and coalesce(v_caller_paid, false) and not coalesce(v_remaining_paid, false)
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
