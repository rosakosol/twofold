create or replace function public.debug_admin_count()
returns bigint language sql security definer set search_path = public as $$
  select count(*) from public.feedback_admins;
$$;
grant execute on function public.debug_admin_count() to anon, authenticated;
