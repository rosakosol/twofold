-- ---------------------------------------------------------------------------
-- Answering from the console
-- ---------------------------------------------------------------------------
--
-- The queue could be read but not answered, which left support in two places: the conversation in
-- the console, the reply in Zoho, and no record in either of what the other had done. `send-support-reply`
-- closes that. These are the two database halves of it.
--
-- Both are service-role only and take an explicit actor, following `admin_scrub_account`: the edge
-- function verifies the caller is a support admin using the CALLER's own client, then does the work
-- with the service key. `auth.uid()` is null under that key, so the actor has to be passed — an
-- audit row attributed to "the service role" names nobody, and naming somebody is the only reason
-- the row exists.

-- ---------------------------------------------------------------------------
-- Messages need a defined order
-- ---------------------------------------------------------------------------
--
-- `created_at` alone is not one. Two messages written in the same instant sort arbitrarily, and
-- that is not hypothetical: a reply recorded in the same transaction as an inbound message shares a
-- timestamp exactly, because `now()` is frozen for the length of a transaction. A conversation that
-- renders its last two messages in a random order is one nobody can read, and "their last message"
-- — which decides what our reply answers — becomes a coin toss.
--
-- An identity column is monotonic by insertion, which is precisely the order a conversation
-- happened in.
alter table public.support_requests
  add column if not exists seq bigint generated always as identity;

create index if not exists support_requests_thread_seq_idx
  on public.support_requests (thread_id, seq desc);

-- ---------------------------------------------------------------------------
-- What the mail needs
-- ---------------------------------------------------------------------------
--
-- Gathered in one call because every one of these is a round trip, and a reply that takes four of
-- them before it starts composing is a reply somebody gives up on.
--
-- `last_inbound_message_id` is what goes in In-Reply-To. It threads the reply inside THEIR mail
-- client, which is a separate mechanism from the token that threads it inside ours: the token comes
-- back to us on their next reply, the In-Reply-To makes our message sit under theirs in their inbox.
-- Neither substitutes for the other.

create or replace function public.support_thread_for_reply(p_thread_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = private, public, auth
as $$
declare
  v_result jsonb;
begin
  if auth.role() <> 'service_role' and not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'thread_id', t.id,
    'token', t.token,
    'email', t.email,
    'name', (
      select r.name from public.support_requests r
      where r.thread_id = t.id and r.direction = 'inbound' and r.name is not null
      order by r.seq desc limit 1
    ),
    'subject', t.subject,
    'status', t.status,
    'last_inbound_message_id', (
      select r.message_id from public.support_requests r
      where r.thread_id = t.id and r.direction = 'inbound' and r.message_id is not null
      order by r.seq desc limit 1
    )
  )
  into v_result
  from public.support_threads t
  where t.id = p_thread_id;

  return v_result;
end;
$$;

revoke execute on function public.support_thread_for_reply(uuid) from anon;
grant execute on function public.support_thread_for_reply(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Recording what was sent
-- ---------------------------------------------------------------------------
--
-- Written only after the mail has actually gone. A row claiming we answered when the send failed is
-- worse than no row: it tells whoever reads the queue next that this is handled, and the person
-- waiting never hears anything.
--
-- `p_close` is separate from the write rather than assumed, because answering is usually the end of
-- a conversation but not always — a reply asking for a screenshot leaves it open, and the composer
-- offers the choice.

create or replace function public.record_support_reply(
  p_thread_id uuid,
  p_actor uuid,
  p_body text,
  p_close boolean default true,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = private, public
as $$
declare
  v_id uuid;
  v_thread public.support_threads;
begin
  if auth.role() <> 'service_role' then
    raise exception 'not authorised' using errcode = '42501';
  end if;
  if p_actor is null then
    raise exception 'an actor is required' using errcode = '22023';
  end if;
  if coalesce(trim(p_body), '') = '' then
    raise exception 'a reply cannot be empty' using errcode = '22023';
  end if;

  select * into v_thread from public.support_threads where id = p_thread_id;
  if not found then
    raise exception 'no such thread';
  end if;

  insert into public.support_requests (
    thread_id, profile_id, email, category, subject, message, source, direction,
    thread_key, created_at
  )
  values (
    p_thread_id, v_thread.profile_id, v_thread.email, 'Email',
    v_thread.subject, trim(p_body), 'email', 'outbound',
    v_thread.thread_key, now()
  )
  returning id into v_id;

  -- Our own reply advances the conversation but must NOT reopen it — that is what an incoming
  -- message does. Writing `status` unconditionally here would undo a close performed in the same
  -- action, moments earlier, by this very function.
  update public.support_threads
  set last_message_at = now(),
      status = case when p_close then 'closed' else status end,
      handled_by = case when p_close then p_actor else handled_by end,
      handled_at = case when p_close then now() else handled_at end,
      handler_note = coalesce(nullif(trim(p_note), ''), handler_note)
  where id = p_thread_id;

  insert into private.admin_audit_log (actor_id, action, subject_profile_id, reason, details)
  values (
    p_actor, 'support.reply', v_thread.profile_id, nullif(trim(p_note), ''),
    jsonb_build_object('thread_id', p_thread_id, 'closed', p_close)
  );

  return v_id;
end;
$$;

revoke execute on function public.record_support_reply(uuid, uuid, text, boolean, text)
  from public, anon, authenticated;
grant execute on function public.record_support_reply(uuid, uuid, text, boolean, text) to service_role;

-- ---------------------------------------------------------------------------
-- The queue, ordered by insertion within a conversation
-- ---------------------------------------------------------------------------
--
-- Same change as above, for the same reason: `created_at desc` alone leaves two messages written in
-- one instant in an arbitrary order, and the newest is the one the console makes the headline.

drop function if exists public.admin_support_requests(text, integer);

create or replace function public.admin_support_requests(
  p_status text default 'open',
  p_limit integer default 100
)
returns table (
  id uuid, thread_id uuid, thread_token text, thread_size bigint, thread_position bigint,
  thread_last_at timestamptz, thread_status text, thread_handler_note text, thread_handled_at timestamptz,
  profile_id uuid, matched_profile_id uuid, email text, name text, category text, subject text,
  message text, source text, direction text, created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;

  return query
    with threads as (
      select * from public.support_threads t
      where p_status is null or t.status = p_status
      order by t.last_message_at desc
      limit least(greatest(coalesce(p_limit, 100), 1), 200)
    )
    select
      r.id, t.id, t.token,
      count(*) over (partition by t.id),
      row_number() over (partition by t.id order by r.seq desc),
      t.last_message_at, t.status, t.handler_note, t.handled_at,
      r.profile_id,
      coalesce(t.profile_id, r.profile_id,
               (select u.id from auth.users u where lower(u.email) = lower(t.email) limit 1)),
      r.email, r.name, r.category, r.subject, r.message, r.source,
      coalesce(r.direction, 'inbound'), r.created_at
    from threads t
    join public.support_requests r on r.thread_id = t.id
    order by t.last_message_at desc, t.id, r.seq desc;
end;
$$;

revoke execute on function public.admin_support_requests(text, integer) from anon;
grant execute on function public.admin_support_requests(text, integer) to authenticated;
