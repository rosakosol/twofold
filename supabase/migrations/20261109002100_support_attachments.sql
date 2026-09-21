-- ---------------------------------------------------------------------------
-- Files on a support conversation
-- ---------------------------------------------------------------------------
--
-- Half of support is "send me a screenshot" and "here is the fix, see the attached". Neither was
-- possible from the console, so both were reasons to go back to Zoho — which is the two-places
-- problem the queue was built to end.
--
-- This is the outbound half: files attached to a reply we send. Inbound attachments are a separate
-- problem, because Zoho's webhook does not carry them at all and fetching them needs the Mail API
-- and an OAuth token.
--
-- ---------------------------------------------------------------------------
-- The bytes live in R2, not here
-- ---------------------------------------------------------------------------
--
-- Postgres is a poor place for files, and the app already has somewhere better: avatars, memory
-- photos, drawing pads and flight documents are all in R2 (see `_shared/r2.ts` and `storage-url`).
-- This row is a pointer plus the facts needed to attach it to an email — the name to show, the type
-- to declare, and the size to refuse on.
--
-- The key is generated server-side rather than taken from the caller. A client-chosen key is a
-- client-chosen path, and a path like `../avatars/{someone}/avatar.jpg` is how an upload endpoint
-- becomes a way to overwrite other people's files.

create table if not exists public.support_attachments (
  id uuid primary key default gen_random_uuid(),

  thread_id uuid not null references public.support_threads (id) on delete cascade,

  -- Null between reserving the upload and sending the message it belongs to. An attachment whose
  -- reply was never sent is a dangling file, which the purge below sweeps up.
  request_id uuid references public.support_requests (id) on delete cascade,

  -- What the recipient sees. Kept separate from the key, because the key is ours and opaque while
  -- this is theirs and arbitrary.
  filename text not null,
  content_type text not null,
  size_bytes bigint,

  -- Where it actually is. Unique so a retried reservation cannot produce two rows pointing at one
  -- object, and so a stale row cannot be silently reused for different bytes.
  r2_key text not null unique,

  direction text not null default 'outbound' check (direction in ('inbound', 'outbound')),
  created_at timestamptz not null default now()
);

comment on table public.support_attachments is
  'Files on a support conversation. The bytes are in R2 like every other file this app holds; this '
  'row is the pointer plus what an email needs — name, type, size. Keys are generated server-side, '
  'never accepted from a caller.';

create index if not exists support_attachments_thread_idx
  on public.support_attachments (thread_id, created_at);
create index if not exists support_attachments_request_idx
  on public.support_attachments (request_id);
-- For the sweep below.
create index if not exists support_attachments_dangling_idx
  on public.support_attachments (created_at) where request_id is null;

alter table public.support_attachments enable row level security;
revoke all on public.support_attachments from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Reserving an upload
-- ---------------------------------------------------------------------------
--
-- Called before the file exists, so the edge function can sign a PUT for a key nobody chose. The
-- limits are enforced here rather than only in the UI: a presigned PUT is a capability, and one
-- handed out for a 200MB file is a 200MB file in the bucket whatever the form said.

create or replace function public.reserve_support_attachment(
  p_thread_id uuid,
  p_filename text,
  p_content_type text,
  p_size_bytes bigint
)
returns jsonb
language plpgsql
security definer
set search_path = private, public
as $$
declare
  v_id uuid := gen_random_uuid();
  v_clean text;
  v_key text;
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;
  if not exists (select 1 from public.support_threads where id = p_thread_id) then
    raise exception 'no such thread';
  end if;
  if coalesce(trim(p_filename), '') = '' then
    raise exception 'a filename is required' using errcode = '22023';
  end if;

  -- 10MB. Chosen against what the SEND has to do rather than what the bucket can hold: the reply
  -- function pulls every attachment into memory to hand denomailer a Uint8Array, and an edge
  -- function has a finite amount of it. Well under the ~25MB most mail servers refuse above, too.
  if coalesce(p_size_bytes, 0) <= 0 or p_size_bytes > 10 * 1024 * 1024 then
    raise exception 'attachments must be between 1 byte and 10MB' using errcode = '22023';
  end if;

  if (select count(*) from public.support_attachments
      where thread_id = p_thread_id and request_id is null) >= 5 then
    raise exception 'too many pending attachments on this conversation' using errcode = '22023';
  end if;

  -- The displayed name is kept as typed; the KEY is built from our own uuid and a sanitised
  -- extension, so nothing a caller writes reaches the path.
  v_clean := lower(coalesce((regexp_match(p_filename, '\.([a-zA-Z0-9]{1,8})$'))[1], 'bin'));
  v_key := 'support/' || p_thread_id::text || '/' || v_id::text || '.' || v_clean;

  insert into public.support_attachments (id, thread_id, filename, content_type, size_bytes, r2_key)
  values (v_id, p_thread_id, left(trim(p_filename), 255),
          coalesce(nullif(trim(p_content_type), ''), 'application/octet-stream'),
          p_size_bytes, v_key);

  return jsonb_build_object('id', v_id, 'key', v_key);
end;
$$;

revoke execute on function public.reserve_support_attachment(uuid, text, text, bigint) from anon;
grant execute on function public.reserve_support_attachment(uuid, text, text, bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- Reading them back
-- ---------------------------------------------------------------------------

create or replace function public.support_attachments_for_send(p_ids uuid[])
returns table (id uuid, filename text, content_type text, r2_key text, thread_id uuid)
language plpgsql
stable
security definer
set search_path = private, public, auth
as $$
begin
  if auth.role() <> 'service_role' and not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;

  return query
    select a.id, a.filename, a.content_type, a.r2_key, a.thread_id
    from public.support_attachments a
    where a.id = any(p_ids) and a.request_id is null
    order by a.created_at;
end;
$$;

revoke execute on function public.support_attachments_for_send(uuid[]) from anon;
grant execute on function public.support_attachments_for_send(uuid[]) to authenticated, service_role;

-- Attaches the reserved files to the message that actually carried them, which is also what stops
-- the sweep below collecting them.
create or replace function public.attach_support_attachments(p_ids uuid[], p_request_id uuid)
returns integer
language plpgsql
security definer
set search_path = private, public, auth
as $$
declare
  v_count integer;
begin
  if auth.role() <> 'service_role' then
    raise exception 'not authorised' using errcode = '42501';
  end if;

  update public.support_attachments
  set request_id = p_request_id
  where id = any(p_ids) and request_id is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public.attach_support_attachments(uuid[], uuid) from public, anon, authenticated;
grant execute on function public.attach_support_attachments(uuid[], uuid) to service_role;

-- ---------------------------------------------------------------------------
-- Files whose reply was never sent
-- ---------------------------------------------------------------------------
--
-- Somebody attaches a screenshot, changes their mind, closes the tab. The row and the object both
-- survive with nothing pointing at them. Swept after a day — long enough that no real compose
-- session is interrupted, short enough that the bucket does not accumulate everything anybody ever
-- thought about sending.
--
-- Returns the keys rather than deleting objects itself, because Postgres cannot reach R2. The
-- caller is responsible for removing them; a row deleted here whose object survives is a small leak,
-- and an object deleted whose row survives would be a broken attachment, so this order is the safe
-- one.

create or replace function private.purge_dangling_support_attachments(p_older_than interval default '1 day')
returns table (r2_key text)
language plpgsql
security definer
set search_path = private, public
as $$
begin
  return query
    delete from public.support_attachments
    where request_id is null and created_at < now() - p_older_than
    returning public.support_attachments.r2_key;
end;
$$;

revoke all on function private.purge_dangling_support_attachments(interval) from public, anon, authenticated;
