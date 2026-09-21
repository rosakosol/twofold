-- ---------------------------------------------------------------------------
-- Fetching the attachments Zoho's webhook does not send
-- ---------------------------------------------------------------------------
--
-- Somebody emails a screenshot and the console shows the words without it. The webhook carries no
-- attachments — confirmed by people listing every field it delivers — but it carries `messageId`,
-- `folderId` and `zuid`, which is what the Mail API needs to go and get them.
--
-- ---------------------------------------------------------------------------
-- Why a sweep, and not inline in the webhook
-- ---------------------------------------------------------------------------
--
-- Fetching means an OAuth exchange, a metadata call, a download per file and an upload per file to
-- R2. Doing that inside the webhook would make Zoho wait on all of it, and Zoho's answer to waiting
-- is to retry — which means doing it all again, and eventually disabling a webhook that "fails".
--
-- So ingest records the message and returns immediately, and a cron sweep collects what is
-- outstanding. That also makes every failure retried for free: a message stays `pending` until it
-- is genuinely resolved, so a Zoho outage delays attachments rather than losing them.

alter table public.support_requests
  add column if not exists attachments_state text not null default 'none'
    check (attachments_state in ('none', 'pending', 'done', 'failed'));

comment on column public.support_requests.attachments_state is
  '`pending` once an emailed message is recorded with the handles needed to ask Zoho about its '
  'attachments; `done` when asked and settled (including "it had none"); `failed` after repeated '
  'refusals. Anything not from email is `none` — there is nothing to ask about.';

-- The sweep's working set. Partial, because it is only ever queried for one value.
create index if not exists support_requests_attachments_pending_idx
  on public.support_requests (created_at) where attachments_state = 'pending';

-- Emailed messages with the handles are marked for the sweep; everything else has nothing to ask.
create or replace function public.ingest_support_email(
  p_message_id text,
  p_email text,
  p_name text,
  p_subject text,
  p_message text,
  p_received_at timestamptz default now(),
  p_to_address text default null,
  p_folder_id text default null,
  p_zoho_account_id text default null
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

  if nullif(trim(p_message_id), '') is not null
     and exists (select 1 from public.support_requests where message_id = trim(p_message_id)) then
    return null;
  end if;

  select u.id into v_profile from auth.users u where lower(u.email) = v_email_norm limit 1;
  v_thread := private.resolve_support_thread(p_to_address, p_subject, v_email_norm, v_profile, v_at);

  insert into public.support_requests (
    thread_id, message_id, folder_id, zoho_account_id, profile_id, email, name, category,
    subject, message, source, thread_key, created_at, attachments_state
  )
  values (
    v_thread, nullif(trim(p_message_id), ''), nullif(trim(p_folder_id), ''),
    nullif(trim(p_zoho_account_id), ''), v_profile, v_email_norm, nullif(trim(p_name), ''),
    'Email', nullif(trim(p_subject), ''), left(coalesce(trim(p_message), ''), 20000), 'email',
    private.support_thread_key(p_subject, v_email_norm), v_at,
    -- Without a message id there is nothing to ask Zoho about, so there is no point asking.
    case when nullif(trim(p_message_id), '') is not null then 'pending' else 'none' end
  )
  on conflict (message_id) where message_id is not null do nothing
  returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function public.ingest_support_email(text, text, text, text, text, timestamptz, text, text, text)
  from public, anon, authenticated;
grant execute on function public.ingest_support_email(text, text, text, text, text, timestamptz, text, text, text)
  to service_role;

-- ---------------------------------------------------------------------------
-- What the sweep asks for, and what it reports back
-- ---------------------------------------------------------------------------

create or replace function public.support_messages_awaiting_attachments(p_limit integer default 20)
returns table (id uuid, thread_id uuid, message_id text, folder_id text, zoho_account_id text)
language plpgsql
stable
security definer
set search_path = private, public, auth
as $$
begin
  if auth.role() <> 'service_role' then
    raise exception 'not authorised' using errcode = '42501';
  end if;
  return query
    select r.id, r.thread_id, r.message_id, r.folder_id, r.zoho_account_id
    from public.support_requests r
    where r.attachments_state = 'pending'
    order by r.created_at
    limit least(greatest(coalesce(p_limit, 20), 1), 100);
end;
$$;

revoke execute on function public.support_messages_awaiting_attachments(integer) from public, anon, authenticated;
grant execute on function public.support_messages_awaiting_attachments(integer) to service_role;

-- One call per message, after its files are in R2. Recording the rows and settling the state
-- together means a message can never be marked done with its attachments half-written.
create or replace function public.record_inbound_attachments(
  p_request_id uuid,
  p_attachments jsonb,
  p_state text default 'done'
)
returns integer
language plpgsql
security definer
set search_path = private, public, auth
as $$
declare
  v_thread uuid;
  v_count integer := 0;
  v_item jsonb;
begin
  if auth.role() <> 'service_role' then
    raise exception 'not authorised' using errcode = '42501';
  end if;
  if p_state not in ('done', 'failed', 'pending') then
    raise exception 'unknown state' using errcode = '22023';
  end if;

  select thread_id into v_thread from public.support_requests where id = p_request_id;
  if v_thread is null then
    raise exception 'no such message';
  end if;

  for v_item in select * from jsonb_array_elements(coalesce(p_attachments, '[]'::jsonb))
  loop
    insert into public.support_attachments (
      thread_id, request_id, filename, content_type, size_bytes, r2_key, direction
    )
    values (
      v_thread, p_request_id,
      left(coalesce(v_item->>'filename', 'attachment'), 255),
      coalesce(nullif(v_item->>'content_type', ''), 'application/octet-stream'),
      nullif(v_item->>'size_bytes', '')::bigint,
      v_item->>'r2_key',
      'inbound'
    )
    -- A re-run after a partial failure re-uploads to the same key and must not duplicate the row.
    on conflict (r2_key) do nothing;
    v_count := v_count + 1;
  end loop;

  update public.support_requests set attachments_state = p_state where id = p_request_id;
  return v_count;
end;
$$;

revoke execute on function public.record_inbound_attachments(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function public.record_inbound_attachments(uuid, jsonb, text) to service_role;

-- ---------------------------------------------------------------------------
-- Reading them in the console
-- ---------------------------------------------------------------------------

create or replace function public.admin_thread_attachments(p_thread_id uuid)
returns table (id uuid, request_id uuid, filename text, content_type text, size_bytes bigint,
               r2_key text, direction text, created_at timestamptz)
language plpgsql
stable
security definer
set search_path = private, public
as $$
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;
  return query
    select a.id, a.request_id, a.filename, a.content_type, a.size_bytes, a.r2_key, a.direction, a.created_at
    from public.support_attachments a
    where a.thread_id = p_thread_id and a.request_id is not null
    order by a.created_at;
end;
$$;

revoke execute on function public.admin_thread_attachments(uuid) from anon;
grant execute on function public.admin_thread_attachments(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- The sweep
-- ---------------------------------------------------------------------------
--
-- Every five minutes, not nightly. An attachment that arrives with a support request is part of the
-- request — somebody reading the queue ten minutes later should see the screenshot the message
-- refers to, not a note saying one was promised.

create or replace function private.trigger_fetch_support_attachments()
returns void
language plpgsql
security definer
set search_path = public, extensions, vault
as $$
declare
  project_url text;
  service_key text;
begin
  select decrypted_secret into project_url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into service_key from vault.decrypted_secrets where name = 'service_role_key';

  if project_url is null or service_key is null then
    raise notice 'fetch-support-attachments: project_url/service_role_key not set in Vault yet, skipping this run';
    return;
  end if;

  perform net.http_post(
    url := project_url || '/functions/v1/fetch-support-attachments',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || service_key),
    body := '{}'::jsonb
  );
end;
$$;

-- Offset from the quarter hours, where the streak reminders already sit.
select cron.schedule(
  'fetch-support-attachments',
  '3,8,13,18,23,28,33,38,43,48,53,58 * * * *',
  'select private.trigger_fetch_support_attachments();'
);
