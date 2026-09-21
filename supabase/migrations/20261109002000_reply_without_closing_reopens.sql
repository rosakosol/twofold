-- ---------------------------------------------------------------------------
-- Replying without closing means the conversation is not finished
-- ---------------------------------------------------------------------------
--
-- `record_support_reply` left `status` untouched when `p_close` was false, on the reasoning that
-- our own reply should not reopen a conversation because that is what an incoming message does.
--
-- That conflated two different things. An incoming message reopening a closed thread is right: they
-- wrote again. But turning the composer's "close after sending" switch OFF is an explicit statement
-- that this exchange is not finished — and the only reason to say so is that a response is expected.
--
-- Left as it was, replying to a closed conversation without closing it left it closed: outside the
-- default filter, invisible to whoever reads the queue next, and waiting on a reply that nobody is
-- watching for. If it never comes, nothing ever surfaces it again.
--
-- The switch now sets the state outright rather than half of it. On means closed, off means open,
-- whatever the conversation was before.

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

  update public.support_threads
  set last_message_at = now(),
      -- The switch says whether this is done. Off means open, even if it was closed a moment ago —
      -- somebody deliberately choosing not to close is somebody expecting an answer.
      status = case when p_close then 'closed' else 'open' end,
      handled_by = case when p_close then p_actor else null end,
      handled_at = case when p_close then now() else null end,
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
