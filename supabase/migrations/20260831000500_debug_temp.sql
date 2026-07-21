create or replace function public.debug_check_admin_status(p_email text)
returns table(user_id uuid, email text, is_admin boolean, admin_table_count bigint)
language sql security definer set search_path = public as $$
  select
    u.id,
    u.email,
    exists(select 1 from public.feedback_admins fa where fa.profile_id = u.id),
    (select count(*) from public.feedback_admins)
  from auth.users u
  where u.email = p_email;
$$;
grant execute on function public.debug_check_admin_status(text) to anon, authenticated;
