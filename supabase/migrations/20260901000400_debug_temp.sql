create or replace function public.debug_notification_prefs(p_profile_id uuid)
returns table(has_pref_row boolean, prefs jsonb)
language sql security definer set search_path = public as $$
  select
    (select count(*) > 0 from public.notification_preferences where profile_id = p_profile_id),
    (select to_jsonb(np) from public.notification_preferences np where np.profile_id = p_profile_id);
$$;
grant execute on function public.debug_notification_prefs(uuid) to anon, authenticated;
