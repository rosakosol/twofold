create or replace function public.debug_waitlist_count()
returns bigint language sql security definer set search_path = public as $$
  select count(*) from public.waitlist_signups;
$$;
grant execute on function public.debug_waitlist_count() to anon, authenticated;
