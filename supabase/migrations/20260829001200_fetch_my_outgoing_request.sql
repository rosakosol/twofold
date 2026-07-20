-- The requester side of a pending connection request has no RLS-visible way to read the
-- inviter's name/avatar before a couple exists (profiles_select_self_or_partner only allows
-- reading your own row or an actual couple-partner's) — needed so RootView can show "{name}
-- needs to accept" instead of the forced paywall while a request is still pending (see
-- fetch_pending_connection_requests, the same shape for the inviter's own side).

create or replace function public.fetch_my_outgoing_connection_request()
returns table (
  id uuid,
  inviter_id uuid,
  inviter_first_name text,
  inviter_avatar_path text,
  created_at timestamptz
)
language sql
security definer
set search_path = public
stable
as $$
  select cr.id, cr.inviter_id, p.first_name, p.avatar_path, cr.created_at
  from public.connection_requests cr
  join public.profiles p on p.id = cr.inviter_id
  where cr.requester_id = auth.uid() and cr.status = 'pending'
  order by cr.created_at desc
  limit 1;
$$;

revoke all on function public.fetch_my_outgoing_connection_request() from public;
grant execute on function public.fetch_my_outgoing_connection_request() to authenticated;
