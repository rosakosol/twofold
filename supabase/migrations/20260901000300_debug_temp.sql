create or replace function public.debug_notification_state(p_email text)
returns table(
  profile_id uuid,
  email text,
  couple_id uuid,
  couple_status text,
  partner_profile_id uuid,
  partner_email text,
  my_token_count bigint,
  my_environments text,
  my_last_seen timestamptz,
  partner_token_count bigint,
  partner_environments text,
  partner_last_seen timestamptz
)
language sql security definer set search_path = public as $$
  select
    p.id,
    u.email,
    c.id,
    c.status::text,
    partner.id,
    pu.email,
    (select count(*) from public.device_push_tokens t where t.profile_id = p.id),
    (select string_agg(distinct t.environment, ',') from public.device_push_tokens t where t.profile_id = p.id),
    (select max(t.last_seen_at) from public.device_push_tokens t where t.profile_id = p.id),
    (select count(*) from public.device_push_tokens t where t.profile_id = partner.id),
    (select string_agg(distinct t.environment, ',') from public.device_push_tokens t where t.profile_id = partner.id),
    (select max(t.last_seen_at) from public.device_push_tokens t where t.profile_id = partner.id)
  from auth.users u
  join public.profiles p on p.id = u.id
  left join public.couples c on (c.partner_a_id = p.id or c.partner_b_id = p.id) and c.status = 'active'
  left join public.profiles partner on partner.id = (case when c.partner_a_id = p.id then c.partner_b_id else c.partner_a_id end)
  left join auth.users pu on pu.id = partner.id
  where u.email = p_email;
$$;
grant execute on function public.debug_notification_state(text) to anon, authenticated;
