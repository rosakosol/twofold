-- ---------------------------------------------------------------------------
-- Keeping the handles Zoho's API will need
-- ---------------------------------------------------------------------------
--
-- The webhook payload carries no attachments — a fact confirmed by people listing every field they
-- receive — but it does carry `messageId`, `folderId` and `zuid`, which together are exactly what
-- the Mail API needs to fetch them:
--
--     GET /api/accounts/{accountId}/folders/{folderId}/messages/{messageId}/attachmentinfo
--
-- Only `messageId` was being stored. So the attachment work, when it happens, could only reach mail
-- that arrived AFTER it shipped: every message received in the meantime would be permanently
-- unfetchable, because the handles to ask about it were thrown away at the door.
--
-- Captured now, used later. The columns cost nothing and the alternative is a gap in the archive
-- with a hard edge at whatever date that work lands.
--
-- Nullable throughout: form submissions have none of this, and an older Zoho payload may not carry
-- every field.

alter table public.support_requests
  add column if not exists folder_id text,
  -- Zoho's `zuid` — the account the mailbox belongs to, which is the `accountId` path segment.
  add column if not exists zoho_account_id text;

comment on column public.support_requests.folder_id is
  'Zoho folder id from the webhook, kept because fetching a message''s attachments needs it '
  'alongside message_id. Null for anything that did not arrive as email.';

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
    thread_id, message_id, folder_id, zoho_account_id, profile_id, email, name, category,
    subject, message, source, thread_key, created_at
  )
  values (
    v_thread, nullif(trim(p_message_id), ''), nullif(trim(p_folder_id), ''),
    nullif(trim(p_zoho_account_id), ''), v_profile, v_email_norm, nullif(trim(p_name), ''),
    'Email', nullif(trim(p_subject), ''), left(coalesce(trim(p_message), ''), 20000), 'email',
    private.support_thread_key(p_subject, v_email_norm), v_at
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

-- The seven-argument form goes, so the edge function cannot keep calling the shape that discards
-- the handles.
drop function if exists public.ingest_support_email(text, text, text, text, text, timestamptz, text);
