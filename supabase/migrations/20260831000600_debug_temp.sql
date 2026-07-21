create or replace function public.debug_check_profile_exists(p_user_id uuid)
returns boolean
language sql security definer set search_path = public as $$
  select exists(select 1 from public.profiles where id = p_user_id);
$$;
grant execute on function public.debug_check_profile_exists(uuid) to anon, authenticated;
