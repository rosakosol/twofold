-- Premium content was reachable on a plus subscription.
--
-- `couple_effective_tier` ORed `subscription_tier` across both partners without checking
-- `subscription_active`. That column is deliberately never cleared when a subscription lapses — see
-- BackendService.subscriptionTier, which compensates by only trusting a tier whose row is also
-- active — so a stale 'premium' sat on the profile indefinitely.
--
-- The leak: a couple where one partner's premium has lapsed and the other holds an active *plus*
-- subscription still has access (couple-wide access is an OR over `subscription_active`), and this
-- function then reported 'premium' off the lapsed partner's stale tier. They got premium decks
-- while paying for plus. Same shape for a single user whose own premium lapsed while their partner
-- kept them covered on plus.
--
-- Requiring the tier's own row to be active makes the two columns agree. It's also safe against
-- false negatives: `updateSubscriptionStatus` always writes `subscription_active` and
-- `subscription_tier` in the same call, so an active row's tier is fresh by construction — a
-- premium subscriber is never seen as active-but-not-premium.

create or replace function private.couple_effective_tier(p_couple_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when bool_or(p.subscription_active and coalesce(p.subscription_tier, 'plus') = 'premium') then 'premium'
    else 'plus'
  end
  from public.couples c
  join public.profiles p on p.id in (c.partner_a_id, c.partner_b_id)
  where c.id = p_couple_id;
$$;

-- The solo equivalents inline the same rule against a single profile rather than calling the
-- function above (there's no couple to pass), so they need the same gate or a lapsed solo premium
-- keeps its decks. Both read `subscription_tier` bare today.
create or replace function public.get_daily_question_session()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_couple_id uuid;
  v_local_date date;
  v_session_id uuid;
  v_content_id uuid;
  v_effective_tier text;
  v_tiers text[];
begin
  select couple_id, local_date into v_couple_id, v_local_date from private.viewer_day();

  if v_local_date is null then
    raise exception 'No profile for the current user';
  end if;

  select id into v_session_id
  from public.game_sessions
  where game_type = 'deep_conversations' and is_daily and status != 'abandoned'
    and daily_local_date = v_local_date
    and (
      (v_couple_id is not null and couple_id = v_couple_id)
      or (v_couple_id is null and couple_id is null and initiator_id = auth.uid())
    )
  limit 1;

  if v_session_id is not null then
    return v_session_id;
  end if;

  v_effective_tier := case
    when v_couple_id is not null then private.couple_effective_tier(v_couple_id)
    else coalesce(
      (select case when subscription_active then subscription_tier end from public.profiles where id = auth.uid()),
      'plus'
    )
  end;
  v_tiers := case when v_effective_tier = 'premium' then array['plus', 'premium'] else array['plus'] end;

  select id into v_content_id
  from public.deep_conversation_topics
  where active and tier = any(v_tiers)
    and id not in (
      select gsr.content_id from public.game_session_rounds gsr
      join public.game_sessions gs on gs.id = gsr.session_id
      where gs.game_type = 'deep_conversations'
        and (
          (v_couple_id is not null and gs.couple_id = v_couple_id)
          or (v_couple_id is null and gs.couple_id is null and gs.initiator_id = auth.uid())
        )
    )
  order by random() limit 1;

  if v_content_id is null then
    select id into v_content_id
    from public.deep_conversation_topics where active and tier = any(v_tiers)
    order by random() limit 1;
  end if;

  if v_content_id is null then
    raise exception 'No active discussion content available';
  end if;

  insert into public.game_sessions (couple_id, initiator_id, game_type, status, is_daily, daily_local_date, total_rounds)
  values (v_couple_id, auth.uid(), 'deep_conversations', 'active', true, v_local_date, 1)
  returning id into v_session_id;

  insert into public.game_session_rounds (session_id, round_number, content_id)
  values (v_session_id, 1, v_content_id);

  return v_session_id;
end;
$$;
