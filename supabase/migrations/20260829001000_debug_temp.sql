-- TEMPORARY debug function — will be dropped by a follow-up migration immediately after use.
create or replace function public.debug_check_invite_codes()
returns table (code text, status text, first_name text, expires_at timestamptz, now_is timestamptz)
language sql
security definer
set search_path = public
stable
as $$
  select i.code, i.status, p.first_name, i.expires_at, now()
  from public.invite_codes i
  join public.profiles p on p.id = i.inviter_id
  order by i.created_at desc
  limit 10;
$$;

grant execute on function public.debug_check_invite_codes() to anon, authenticated;
