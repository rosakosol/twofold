-- ---------------------------------------------------------------------------
-- A reply belongs to the conversation it is replying to
-- ---------------------------------------------------------------------------
--
-- Every message became its own ticket. Somebody writes in, we answer, they say "that worked,
-- thanks" — three rows, two of which need closing, and a queue that grows by every courtesy.
-- Worse: a reply to a ticket already closed appeared as a brand-new open one with no sign of what
-- it was about.
--
-- ---------------------------------------------------------------------------
-- Why the key is derived rather than read
-- ---------------------------------------------------------------------------
--
-- The right way to thread mail is `In-Reply-To` and `References`, which point at the Message-ID
-- they answer. Zoho's outgoing webhook does not send them — its documented payload carries
-- `messageId` and no reference headers at all — so there is nothing to follow.
--
-- What is available is the subject and the sender, and mail clients have a strong convention:
-- a reply keeps the subject and prefixes it. So the key is the subject with those prefixes
-- stripped, plus the sender's address. `Re: Cannot sign in` from jo@ threads onto `Cannot sign in`
-- from jo@.
--
-- The failure mode is honest and worth stating: two unrelated messages from the same person with
-- the same subject merge into one thread. For a subject like "Help" that will occasionally happen.
-- The alternative — every message standing alone — is wrong far more often, because most mail
-- after the first IS a reply. If the payload ever grows reference headers, they should be
-- preferred and this kept as the fallback.

create or replace function private.support_thread_key(p_subject text, p_email text)
returns text
language sql
immutable
as $$
  select
    coalesce(
      nullif(
        trim(
          regexp_replace(
            -- Strip any run of reply/forward prefixes, in the languages a mail client is likely to
            -- emit, including the "Re[2]:" form Outlook produces on a long thread.
            regexp_replace(
              lower(coalesce(p_subject, '')),
              '^\s*((re|aw|sv|vs|vb|fw|fwd)\s*(\[[0-9]+\])?\s*:\s*)+',
              '',
              'i'
            ),
            -- Collapse whitespace so "Cannot  sign in" and "Cannot sign in" are one thread.
            '\s+', ' ', 'g'
          )
        ),
        ''
      ),
      '(no subject)'
    ) || '|' || lower(trim(coalesce(p_email, '')));
$$;

comment on function private.support_thread_key(text, text) is
  'Conversation key: the subject with reply/forward prefixes stripped, plus the sender. Derived '
  'because Zoho''s webhook payload carries no In-Reply-To or References to follow. Prefer those '
  'if the payload ever gains them.';

alter table public.support_requests
  add column if not exists thread_key text;

-- Existing rows get keys too, so a reply to something already in the queue threads onto it rather
-- than starting a conversation of one beside it.
update public.support_requests
set thread_key = private.support_thread_key(subject, email)
where thread_key is null;

create index if not exists support_requests_thread_idx
  on public.support_requests (thread_key, created_at desc);

-- ---------------------------------------------------------------------------
-- Both intake paths set it
-- ---------------------------------------------------------------------------

create or replace function public.submit_support_request(
  p_category text,
  p_message text,
  p_subject text default null,
  p_email text default null,
  p_name text default null,
  p_source text default 'app'
)
returns uuid
language plpgsql
security definer
set search_path = private, public, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_id uuid;
begin
  if coalesce(trim(p_message), '') = '' then
    raise exception 'a message is required' using errcode = '22023';
  end if;
  if coalesce(trim(p_category), '') = '' then
    raise exception 'a category is required' using errcode = '22023';
  end if;
  if p_source not in ('app', 'web') then
    raise exception 'unknown source' using errcode = '22023';
  end if;

  -- A signed-in sender's address is their account's, not whatever was posted. This is the field a
  -- reply is sent to, and letting a caller choose it would make this an open relay for support
  -- replies.
  if v_uid is not null then
    select u.email into v_email from auth.users u where u.id = v_uid;
  else
    v_email := nullif(trim(p_email), '');
  end if;

  insert into public.support_requests (
    profile_id, email, name, category, subject, message, source, thread_key
  )
  values (
    v_uid,
    v_email,
    nullif(trim(p_name), ''),
    trim(p_category),
    nullif(trim(p_subject), ''),
    left(trim(p_message), 5000),
    p_source,
    private.support_thread_key(p_subject, v_email)
  )
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.submit_support_request(text, text, text, text, text, text)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- An emailed reply joins its thread, and reopens it
-- ---------------------------------------------------------------------------
--
-- Reopening is the part that matters. Without it, answering somebody, closing the ticket and then
-- receiving "actually it is still broken" leaves that reply attached to a closed conversation,
-- filtered out of the default view, unanswered and invisible.

create or replace function public.ingest_support_email(
  p_message_id text,
  p_email text,
  p_name text,
  p_subject text,
  p_message text,
  p_received_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = private, public, auth
as $$
declare
  v_id uuid;
  v_profile uuid;
  v_thread text;
  v_email_norm text := lower(trim(coalesce(p_email, '')));
begin
  if v_email_norm = '' then
    raise exception 'an address is required' using errcode = '22023';
  end if;

  select u.id into v_profile from auth.users u where lower(u.email) = v_email_norm limit 1;
  v_thread := private.support_thread_key(p_subject, v_email_norm);

  insert into public.support_requests (
    message_id, profile_id, email, name, category, subject, message, source, thread_key, created_at
  )
  values (
    nullif(trim(p_message_id), ''),
    v_profile,
    v_email_norm,
    nullif(trim(p_name), ''),
    'Email',
    nullif(trim(p_subject), ''),
    left(coalesce(trim(p_message), ''), 20000),
    'email',
    v_thread,
    coalesce(p_received_at, now())
  )
  on conflict (message_id) where message_id is not null do nothing
  returning id into v_id;

  -- Only for a message that actually landed. A redelivery must not reopen a thread somebody has
  -- just finished dealing with.
  if v_id is not null then
    update public.support_requests
    set status = 'open', handled_at = null, handled_by = null
    where thread_key = v_thread and status = 'closed';
  end if;

  return v_id;
end;
$$;

revoke execute on function public.ingest_support_email(text, text, text, text, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.ingest_support_email(text, text, text, text, text, timestamptz)
  to service_role;

-- ---------------------------------------------------------------------------
-- Closing acts on the conversation, not the message
-- ---------------------------------------------------------------------------
--
-- "Dealt with" is a property of an exchange. Closing one message of three and leaving the rest open
-- is not a state anybody means, and it is the state the per-row version produced every time.

create or replace function public.admin_set_support_request_status(
  p_id uuid,
  p_status text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = private, public
as $$
declare
  v_thread text;
  v_subject uuid;
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;
  if p_status not in ('open', 'closed') then
    raise exception 'unknown status' using errcode = '22023';
  end if;

  select thread_key, profile_id into v_thread, v_subject
  from public.support_requests where id = p_id;

  if v_thread is null then
    raise exception 'no such request';
  end if;

  update public.support_requests
  set status = p_status,
      handled_by = case when p_status = 'closed' then auth.uid() else null end,
      handled_at = case when p_status = 'closed' then now() else null end,
      handler_note = nullif(trim(p_note), '')
  where thread_key = v_thread;

  perform private.record_admin_action(
    'support.' || p_status, v_subject, p_note,
    jsonb_build_object('request_id', p_id, 'thread_key', v_thread)
  );
end;
$$;

revoke execute on function public.admin_set_support_request_status(uuid, text, text) from anon;
grant execute on function public.admin_set_support_request_status(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- The queue reads as conversations
-- ---------------------------------------------------------------------------
--
-- Returns every message, newest thread first and newest message first within it, plus the position
-- and size of each within its conversation so the console can render one entry per thread with the
-- rest folded underneath. Grouping in SQL rather than in the client because "which thread is most
-- recent" is an ordering question, and ordering a grouped list client-side after a LIMIT gives a
-- page that is neither the newest threads nor the newest messages.

-- Dropped first: the return type gains the thread columns, and `create or replace` cannot change
-- the row type an OUT-parameter function returns. Nothing else depends on it — the console calls it
-- by name and is deployed alongside.
drop function if exists public.admin_support_requests(text, integer);

create or replace function public.admin_support_requests(
  p_status text default 'open',
  p_limit integer default 100
)
returns table (
  id uuid,
  thread_key text,
  thread_size bigint,
  thread_position bigint,
  thread_last_at timestamptz,
  profile_id uuid,
  matched_profile_id uuid,
  email text,
  name text,
  category text,
  subject text,
  message text,
  source text,
  status text,
  handler_note text,
  handled_at timestamptz,
  created_at timestamptz
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
    with matching as (
      select r.* from public.support_requests r
      where p_status is null or r.status = p_status
    ),
    threaded as (
      select
        m.*,
        count(*) over (partition by m.thread_key) as t_size,
        row_number() over (partition by m.thread_key order by m.created_at desc) as t_pos,
        max(m.created_at) over (partition by m.thread_key) as t_last
      from matching m
    )
    select
      t.id, t.thread_key, t.t_size, t.t_pos, t.t_last,
      t.profile_id,
      coalesce(t.profile_id, (select u.id from auth.users u where lower(u.email) = lower(t.email) limit 1)),
      t.email, t.name, t.category, t.subject, t.message, t.source, t.status,
      t.handler_note, t.handled_at, t.created_at
    from threaded t
    order by t.t_last desc, t.thread_key, t.created_at desc
    limit least(greatest(coalesce(p_limit, 100), 1), 500);
end;
$$;

revoke execute on function public.admin_support_requests(text, integer) from anon;
grant execute on function public.admin_support_requests(text, integer) to authenticated;
