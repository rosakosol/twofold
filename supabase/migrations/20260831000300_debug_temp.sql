create or replace function public.debug_check_waitlist_row(p_email text)
returns table(email text, created_at timestamptz)
language sql security definer set search_path = public as $$
  select email, created_at from public.waitlist_signups where email = p_email;
$$;
grant execute on function public.debug_check_waitlist_row(text) to anon, authenticated;
