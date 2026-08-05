-- "Send a reminder" nudge for a still-pending outgoing connection request — Home now shows a
-- persistent card for this state instead of forcing a non-dismissable paywall dead-end (the
-- requester can explore the app while waiting, and optionally nudge the inviter). Rate-limited
-- server-side the same way redeem_invite_code throttles code guesses (log table + rolling-window
-- count-then-insert, see 20260829000600_invite_security_and_connection_requests.sql) since this
-- is client-callable and would otherwise let someone fire a push on every app launch.

create table public.connection_request_reminders (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.connection_requests (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  sent_at timestamptz not null default now()
);

create index connection_request_reminders_request_idx
  on public.connection_request_reminders (request_id, sent_at);

alter table public.connection_request_reminders enable row level security;
-- No policies for any client role — only the security-definer RPC below ever touches this table.

create function public.send_connection_request_reminder(p_request_id uuid)
returns public.connection_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.connection_requests;
  v_caller_id uuid := auth.uid();
  v_recent_reminders int;
begin
  if v_caller_id is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_request from public.connection_requests where id = p_request_id for update;

  if not found then
    raise exception 'Connection request not found';
  end if;

  if v_request.requester_id <> v_caller_id then
    raise exception 'Only the person who sent the request can send a reminder';
  end if;

  if v_request.status <> 'pending' then
    raise exception 'This request is no longer pending';
  end if;

  select count(*) into v_recent_reminders
  from public.connection_request_reminders
  where request_id = p_request_id and sent_at > now() - interval '6 hours';

  if v_recent_reminders >= 1 then
    raise exception 'You already sent a reminder recently — try again later.';
  end if;

  insert into public.connection_request_reminders (request_id, sender_id) values (p_request_id, v_caller_id);

  return v_request;
end;
$$;

revoke all on function public.send_connection_request_reminder(uuid) from public;
grant execute on function public.send_connection_request_reminder(uuid) to authenticated;
