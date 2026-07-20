-- Temporary diagnostic — pre-flight check before a manual notification test pass: confirms
-- Sarah/Lucas are paired and each has a registered push token. Dropped again after use.
create or replace function public.debug_notification_preflight()
returns table(
  first_name text,
  profile_id uuid,
  couple_id uuid,
  couple_status text,
  token_count bigint,
  environments text[],
  memory_added_enabled boolean,
  trip_added_enabled boolean,
  drawing_saved_enabled boolean,
  game_started_enabled boolean
)
language sql
security definer
set search_path = public
as $$
  select
    p.first_name,
    p.id,
    c.id,
    c.status,
    (select count(*) from device_push_tokens t where t.profile_id = p.id),
    (select array_agg(distinct t.environment) from device_push_tokens t where t.profile_id = p.id),
    coalesce(np.partner_memory_added, true),
    coalesce(np.partner_trip_added, true),
    coalesce(np.partner_drawing_saved, true),
    coalesce(np.partner_game_started, true)
  from profiles p
  left join couples c on (c.partner_a_id = p.id or c.partner_b_id = p.id) and c.status = 'active'
  left join notification_preferences np on np.profile_id = p.id
  where p.first_name in ('Sarah', 'Lucas');
$$;

grant execute on function public.debug_notification_preflight() to anon, authenticated;
