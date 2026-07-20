-- Temporary diagnostic function — investigating why partners aren't receiving
-- memory-added push notifications. Returns only aggregate counts (no PII),
-- dropped again immediately after use.
create or replace function public.debug_notification_pipeline()
returns table(
  total_push_token_rows bigint,
  sandbox_token_rows bigint,
  production_token_rows bigint,
  total_notification_pref_rows bigint,
  memory_added_disabled_rows bigint,
  total_active_couples bigint,
  memories_last_7_days bigint
)
language sql
security definer
set search_path = public
as $$
  select
    (select count(*) from device_push_tokens),
    (select count(*) from device_push_tokens where environment = 'sandbox'),
    (select count(*) from device_push_tokens where environment = 'production'),
    (select count(*) from notification_preferences),
    (select count(*) from notification_preferences where partner_memory_added = false),
    (select count(*) from couples where status = 'active'),
    (select count(*) from memories where created_at > now() - interval '7 days');
$$;

grant execute on function public.debug_notification_pipeline() to anon, authenticated;
