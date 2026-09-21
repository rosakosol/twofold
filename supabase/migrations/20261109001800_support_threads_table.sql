-- ---------------------------------------------------------------------------
-- A conversation is a row, and it has an address of its own
-- ---------------------------------------------------------------------------
--
-- Two problems, one shape.
--
-- First, threading was a guess. `support_thread_key` derives a key from the subject with reply
-- prefixes stripped plus the sender, because Zoho's webhook sends no In-Reply-To or References.
-- That works for the ordinary case and fails in two: somebody who edits the subject while replying
-- starts a new conversation, and somebody who writes twice under "Help" gets one conversation that
-- is really two.
--
-- Second, status lived on every message. `admin_set_support_request_status` wrote the same value to
-- every row sharing a key, which is duplication kept in step by hand — and a single UPDATE that
-- misses a row leaves a conversation half-closed, a state nothing in the UI can express.
--
-- Both are fixed by making the conversation a row. Status belongs to it, and so does a token.
--
-- ---------------------------------------------------------------------------
-- The token, and why replies can now be threaded for certain
-- ---------------------------------------------------------------------------
--
-- Every thread gets a short random token, and a reply we send carries it in the Reply-To:
--
--     support+t3f9a1c2b7e@twofoldapp.com.au
--
-- Zoho delivers plus-addressed mail to the base mailbox — mail to `support+anything@` arrives in
-- `support@` — and the webhook payload includes `toAddress`. So when they reply, the token comes
-- back to us in a field we already receive, and the conversation is identified exactly rather than
-- inferred from a subject line they may have changed.
--
-- The derived key stays as the fallback, for the first message of a conversation (which has no
-- token to carry, because the conversation does not exist yet) and for anybody replying to an
-- address that predates this.

create table if not exists public.support_threads (
  id uuid primary key default gen_random_uuid(),

  -- Ten hex characters. Long enough that guessing one is pointless, short enough to sit in an
  -- address without looking like an incident. It appears in a Reply-To that the correspondent can
  -- see, so it is random rather than sequential: a guessable token would let somebody post into a
  -- stranger's conversation by emailing the right address.
  token text not null unique default encode(gen_random_bytes(5), 'hex'),

  -- The derived key, kept for matching mail that arrives with no token.
  thread_key text not null,

  -- Denormalised from the first message so the queue can be listed without touching messages.
  subject text,
  email text not null,
  profile_id uuid,

  status text not null default 'open' check (status in ('open', 'closed')),
  handled_by uuid,
  handled_at timestamptz,
  handler_note text,

  created_at timestamptz not null default now(),
  -- What the queue is ordered by. Maintained on insert rather than computed, so listing threads
  -- never has to scan their messages.
  last_message_at timestamptz not null default now()
);

comment on table public.support_threads is
  'One row per conversation. Status lives here rather than on each message, because "dealt with" '
  'is a property of an exchange. `token` appears in the Reply-To of any reply we send, so an '
  'answer comes back identifiable via the webhook''s toAddress rather than guessed from a subject.';

create index if not exists support_threads_open_idx
  on public.support_threads (last_message_at desc) where status = 'open';
create index if not exists support_threads_key_idx
  on public.support_threads (thread_key);

alter table public.support_threads enable row level security;
revoke all on public.support_threads from anon, authenticated;

alter table public.support_requests
  add column if not exists thread_id uuid references public.support_threads (id) on delete cascade;

-- Which way the message went. Everything that exists today is something they sent us; replies we
-- send are recorded here too, so a thread reads as the conversation it is rather than as one side
-- of it.
alter table public.support_requests
  add column if not exists direction text not null default 'inbound'
    check (direction in ('inbound', 'outbound'));

create index if not exists support_requests_thread_id_idx
  on public.support_requests (thread_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Backfill
-- ---------------------------------------------------------------------------
--
-- One thread per distinct key. A conversation counts as open if ANY of its messages was open —
-- the safe direction, since the cost of reopening something already dealt with is a second look,
-- and the cost of closing something unanswered is somebody never hearing back.

insert into public.support_threads (thread_key, subject, email, profile_id, status, handled_by, handled_at, handler_note, created_at, last_message_at)
select
  r.thread_key,
  (array_agg(r.subject order by r.created_at))[1],
  (array_agg(r.email order by r.created_at))[1],
  (array_agg(r.profile_id order by r.created_at))[1],
  case when bool_or(r.status = 'open') then 'open' else 'closed' end,
  (array_agg(r.handled_by order by r.created_at desc))[1],
  max(r.handled_at),
  (array_agg(r.handler_note order by r.created_at desc) filter (where r.handler_note is not null))[1],
  min(r.created_at),
  max(r.created_at)
from public.support_requests r
where r.thread_id is null and r.thread_key is not null and r.email is not null
group by r.thread_key
on conflict do nothing;

update public.support_requests r
set thread_id = t.id
from public.support_threads t
where r.thread_id is null and r.thread_key = t.thread_key;

-- ---------------------------------------------------------------------------
-- Status stops being duplicated
-- ---------------------------------------------------------------------------
--
-- Dropped rather than left in place and ignored. A column that no longer means anything is one
-- somebody reads in two years and believes.

alter table public.support_requests drop column if exists status;
alter table public.support_requests drop column if exists handled_by;
alter table public.support_requests drop column if exists handled_at;
alter table public.support_requests drop column if exists handler_note;

-- ---------------------------------------------------------------------------
-- Finding or starting the right conversation
-- ---------------------------------------------------------------------------
--
-- Resolution order, most certain first:
--
--   1. A token in the recipient address. Exact, and survives an edited subject.
--   2. The derived key. Right for a first message, and for replies to an address sent before
--      tokens existed.
--   3. Neither — a new conversation.

create or replace function private.token_from_address(p_to text)
returns text
language sql
immutable
as $$
  -- `toAddress` can hold several recipients and a display name; the token is looked for anywhere in
  -- it rather than by parsing the list, because any appearance of `+t<hex>` is ours.
  select (regexp_match(coalesce(p_to, ''), '\+t([0-9a-f]{10})', 'i'))[1];
$$;

create or replace function private.resolve_support_thread(
  p_to_address text,
  p_subject text,
  p_email text,
  p_profile_id uuid,
  p_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = private, public
as $$
declare
  v_token text := private.token_from_address(p_to_address);
  v_key text := private.support_thread_key(p_subject, p_email);
  v_id uuid;
begin
  if v_token is not null then
    select id into v_id from public.support_threads where token = v_token;
  end if;

  if v_id is null then
    select id into v_id from public.support_threads
    where thread_key = v_key
    order by last_message_at desc
    limit 1;
  end if;

  if v_id is null then
    insert into public.support_threads (thread_key, subject, email, profile_id, created_at, last_message_at)
    values (v_key, nullif(trim(p_subject), ''), lower(trim(p_email)), p_profile_id, p_at, p_at)
    returning id into v_id;
  else
    -- An arriving message makes the conversation current, and reopens it. Reopening is the case
    -- that matters: a reply to something already closed would otherwise sit behind the default
    -- filter, unanswered and unseen.
    update public.support_threads
    set last_message_at = greatest(last_message_at, p_at),
        status = 'open',
        handled_at = case when status = 'closed' then null else handled_at end,
        handled_by = case when status = 'closed' then null else handled_by end,
        profile_id = coalesce(profile_id, p_profile_id)
    where id = v_id;
  end if;

  return v_id;
end;
$$;

revoke all on function private.resolve_support_thread(text, text, text, uuid, timestamptz)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Both intake paths, on threads
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
  v_thread uuid;
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

  -- No recipient address: a form submission has no token to carry, so this always resolves by the
  -- derived key or starts a conversation.
  v_thread := private.resolve_support_thread(null, p_subject, v_email, v_uid, now());

  insert into public.support_requests (
    thread_id, profile_id, email, name, category, subject, message, source, thread_key
  )
  values (
    v_thread, v_uid, v_email, nullif(trim(p_name), ''), trim(p_category),
    nullif(trim(p_subject), ''), left(trim(p_message), 5000), p_source,
    private.support_thread_key(p_subject, v_email)
  )
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.submit_support_request(text, text, text, text, text, text)
  to anon, authenticated;

-- `p_to_address` is new: it is where the token comes back to us.
create or replace function public.ingest_support_email(
  p_message_id text,
  p_email text,
  p_name text,
  p_subject text,
  p_message text,
  p_received_at timestamptz default now(),
  p_to_address text default null
)
returns uuid
language plpgsql
security definer
set search_path = private, public, auth
as $$
declare
  v_id uuid;
  v_profile uuid;
  v_thread uuid;
  v_email_norm text := lower(trim(coalesce(p_email, '')));
  v_at timestamptz := coalesce(p_received_at, now());
begin
  if v_email_norm = '' then
    raise exception 'an address is required' using errcode = '22023';
  end if;

  -- A redelivery must not touch the thread at all — not its timestamp, and above all not its
  -- status, because reopening something just dealt with on the strength of a duplicate delivery is
  -- indistinguishable from the customer writing again.
  if nullif(trim(p_message_id), '') is not null
     and exists (select 1 from public.support_requests where message_id = trim(p_message_id)) then
    return null;
  end if;

  select u.id into v_profile from auth.users u where lower(u.email) = v_email_norm limit 1;
  v_thread := private.resolve_support_thread(p_to_address, p_subject, v_email_norm, v_profile, v_at);

  insert into public.support_requests (
    thread_id, message_id, profile_id, email, name, category, subject, message, source,
    thread_key, created_at
  )
  values (
    v_thread, nullif(trim(p_message_id), ''), v_profile, v_email_norm, nullif(trim(p_name), ''),
    'Email', nullif(trim(p_subject), ''), left(coalesce(trim(p_message), ''), 20000), 'email',
    private.support_thread_key(p_subject, v_email_norm), v_at
  )
  on conflict (message_id) where message_id is not null do nothing
  returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function public.ingest_support_email(text, text, text, text, text, timestamptz, text)
  from public, anon, authenticated;
grant execute on function public.ingest_support_email(text, text, text, text, text, timestamptz, text)
  to service_role;

-- The six-argument form goes, so the edge function cannot keep calling the shape that ignores the
-- recipient address and therefore never sees a token.
drop function if exists public.ingest_support_email(text, text, text, text, text, timestamptz);

-- ---------------------------------------------------------------------------
-- Reading and closing
-- ---------------------------------------------------------------------------

drop function if exists public.admin_support_requests(text, integer);

create or replace function public.admin_support_requests(
  p_status text default 'open',
  p_limit integer default 100
)
returns table (
  id uuid,
  thread_id uuid,
  thread_token text,
  thread_size bigint,
  thread_position bigint,
  thread_last_at timestamptz,
  thread_status text,
  thread_handler_note text,
  thread_handled_at timestamptz,
  profile_id uuid,
  matched_profile_id uuid,
  email text,
  name text,
  category text,
  subject text,
  message text,
  source text,
  direction text,
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
    with threads as (
      select * from public.support_threads t
      where p_status is null or t.status = p_status
      order by t.last_message_at desc
      limit least(greatest(coalesce(p_limit, 100), 1), 200)
    )
    select
      r.id, t.id, t.token,
      count(*) over (partition by t.id),
      row_number() over (partition by t.id order by r.created_at desc),
      t.last_message_at, t.status, t.handler_note, t.handled_at,
      r.profile_id,
      coalesce(t.profile_id, r.profile_id,
               (select u.id from auth.users u where lower(u.email) = lower(t.email) limit 1)),
      r.email, r.name, r.category, r.subject, r.message, r.source,
      -- Added by the reply work; every existing row is something they sent us.
      coalesce(r.direction, 'inbound'),
      r.created_at
    from threads t
    join public.support_requests r on r.thread_id = t.id
    order by t.last_message_at desc, t.id, r.created_at desc;
end;
$$;

revoke execute on function public.admin_support_requests(text, integer) from anon;
grant execute on function public.admin_support_requests(text, integer) to authenticated;

-- Takes a thread now, not a message. Closing is a statement about the conversation.
create or replace function public.admin_set_support_thread_status(
  p_thread_id uuid,
  p_status text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = private, public
as $$
declare
  v_subject uuid;
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;
  if p_status not in ('open', 'closed') then
    raise exception 'unknown status' using errcode = '22023';
  end if;

  update public.support_threads
  set status = p_status,
      handled_by = case when p_status = 'closed' then auth.uid() else null end,
      handled_at = case when p_status = 'closed' then now() else null end,
      handler_note = nullif(trim(p_note), '')
  where id = p_thread_id
  returning profile_id into v_subject;

  if not found then
    raise exception 'no such thread';
  end if;

  perform private.record_admin_action(
    'support.' || p_status, v_subject, p_note,
    jsonb_build_object('thread_id', p_thread_id)
  );
end;
$$;

revoke execute on function public.admin_set_support_thread_status(uuid, text, text) from anon;
grant execute on function public.admin_set_support_thread_status(uuid, text, text) to authenticated;

drop function if exists public.admin_set_support_request_status(uuid, text, text);
