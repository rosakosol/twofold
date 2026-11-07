-- The support queue stops trusting an email's From address, and stops being floodable (security
-- review, F5 and F11).
--
-- F5. Anybody can write any From address. A reply to a thread's token address with a forged From
-- linked the thread to the forged address's account, while replies still went to the attacker, and
-- the console showed "Open account" with no warning. An admin could be talked into deleting the
-- wrong person.
--
-- So each inbound message now records what proves its sender, and the console shows it:
--
--   * 'account': sent from the app, so the session proves the account.
--   * 'mailbox': came back on the thread's token, from the thread's address. The token only ever went
--     to that mailbox, so this sender can read it. This is the check an admin can ask for: reply, and
--     wait for the answer.
--   * null: anything else. An account may still be matched by address, but as a claim, not a fact.
--
-- A token used from a different address still files the message, because people do reply from an
-- alias, but it links to nobody and the console says so.
--
-- Zoho's SPF and DKIM results are not used: the webhook payload is not known to carry them, and the
-- token proof does not depend on them.
--
-- Existing app messages are marked 'account'. Existing email links stay in place and read as
-- unproven, which is what they are.
--
-- F11. Going straight to submit_support_request skipped the limit in submit-help-message, so one free
-- account could post thousands of rows and push real abuse reports out of the console's list. It now
-- allows a signed-in caller 20 an hour and 50 a day, above the 15 an hour that submit-help-message
-- permits, and shortens the fields that had no cap. The website's service-role calls have no user and
-- keep the route's own limits.

alter table public.support_requests
  add column if not exists sender_proof text
  check (sender_proof in ('account', 'mailbox'));

comment on column public.support_requests.sender_proof is
  'What proves who sent this: account (a signed-in session), mailbox (a reply on the thread token from the thread address), or null (nothing).';

update public.support_requests
set sender_proof = 'account'
where source = 'app' and profile_id is not null and coalesce(direction, 'inbound') = 'inbound';

-- ---------------------------------------------------------------------------
-- Inbound email
-- ---------------------------------------------------------------------------

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
  v_token text := private.token_from_address(p_to_address);
  v_thread_email text;
  v_proof text;
begin
  if v_email_norm = '' then
    raise exception 'an address is required' using errcode = '22023';
  end if;

  if nullif(trim(p_message_id), '') is not null
     and exists (select 1 from public.support_requests where message_id = trim(p_message_id)) then
    return null;
  end if;

  select u.id into v_profile from auth.users u where lower(u.email) = v_email_norm limit 1;

  if v_token is not null then
    select lower(t.email) into v_thread_email from public.support_threads t where t.token = v_token;
    if v_thread_email = v_email_norm then
      v_proof := 'mailbox';
    elsif v_thread_email is not null then
      -- Somebody else's address on this conversation's token. See this migration's header.
      v_profile := null;
    end if;
  end if;

  v_thread := private.resolve_support_thread(p_to_address, p_subject, v_email_norm, v_profile, v_at);

  insert into public.support_requests (
    thread_id, message_id, folder_id, zoho_account_id, profile_id, email, name, category,
    subject, message, source, thread_key, created_at, attachments_state, sender_proof
  )
  values (
    v_thread, nullif(trim(p_message_id), ''), nullif(trim(p_folder_id), ''),
    nullif(trim(p_zoho_account_id), ''), v_profile, v_email_norm, nullif(trim(p_name), ''),
    'Email', nullif(trim(p_subject), ''), left(coalesce(trim(p_message), ''), 20000), 'email',
    private.support_thread_key(p_subject, v_email_norm), v_at,
    -- Without a message id there is nothing to ask Zoho about, so there is no point asking.
    case when nullif(trim(p_message_id), '') is not null then 'pending' else 'none' end,
    v_proof
  )
  on conflict (message_id) where message_id is not null do nothing
  returning id into v_id;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Forms: the app and the website
-- ---------------------------------------------------------------------------

create or replace function public.submit_support_request(
  p_category text,
  p_message text,
  p_subject text default null,
  p_email text default null,
  p_name text default null,
  p_source text default 'app',
  p_reported_profile_id uuid default null,
  p_report_surface text default null
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
  v_reported uuid;
  v_subject text := left(p_subject, 200);
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

  if v_uid is not null then
    if exists (select 1 from public.consume_rate_limit('support_request_hour', 20, interval '1 hour') where not allowed)
       or exists (select 1 from public.consume_rate_limit('support_request_day', 50, interval '1 day') where not allowed) then
      raise exception 'support_request_limit' using errcode = 'P0001';
    end if;
  end if;

  -- A signed-in sender's address is their account's, not whatever was posted. This is the field a
  -- reply is sent to, and letting a caller choose it would make this an open relay for support
  -- replies.
  if v_uid is not null then
    select u.email into v_email from auth.users u where u.id = v_uid;
  else
    v_email := nullif(trim(p_email), '');
    -- One bare address: no display name, no list, nothing that can end a header line. Stricter
    -- than the website's own check only in the characters a real address does not contain.
    if v_email is null
       or length(v_email) > 320
       or v_email !~ '^[^[:space:][:cntrl:]<>,;"@]+@[^[:space:][:cntrl:]<>,;"@]+\.[^[:space:][:cntrl:]<>,;"@]+$' then
      raise exception 'a single valid email address is required' using errcode = '22023';
    end if;
  end if;

  -- See 20261113001100: only a signed-in reporter, only on a report, and never themselves.
  if v_uid is not null and trim(p_category) = 'Report Abuse' and p_reported_profile_id is distinct from v_uid then
    v_reported := p_reported_profile_id;
  end if;

  -- No recipient address: a form submission has no token to carry, so this always resolves by the
  -- derived key or starts a conversation.
  v_thread := private.resolve_support_thread(null, v_subject, v_email, v_uid, now(), v_uid is not null);

  insert into public.support_requests (
    thread_id, profile_id, email, name, category, subject, message, source, thread_key,
    reported_profile_id, report_surface, sender_proof
  )
  values (
    v_thread, v_uid, v_email, left(nullif(trim(p_name), ''), 200), left(trim(p_category), 64),
    nullif(trim(v_subject), ''), left(trim(p_message), 5000), p_source,
    private.support_thread_key(v_subject, v_email),
    v_reported, case when v_reported is not null then left(nullif(trim(p_report_surface), ''), 100) end,
    case when v_uid is not null then 'account' end
  )
  returning id into v_id;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- What the console reads
-- ---------------------------------------------------------------------------

-- Result columns cannot change with create or replace. Dropped and re-created in this migration's
-- one transaction, so there is no moment without it.
drop function public.admin_support_requests(text, integer);

create function public.admin_support_requests(
  p_status text default 'open',
  p_limit integer default 100
)
returns table (
  id uuid, thread_id uuid, thread_token text, thread_size bigint, thread_position bigint,
  thread_last_at timestamptz, thread_status text, thread_handler_note text, thread_handled_at timestamptz,
  profile_id uuid, matched_profile_id uuid, email text, name text, category text, subject text,
  message text, source text, direction text, created_at timestamptz,
  reported_profile_id uuid, reported_name text,
  thread_email text, sender_proof text
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
      -- Matched by address when a thread holds anything but website-form messages. That is a claim
      -- unless sender_proof says otherwise: the console says which.
      coalesce(t.profile_id, r.profile_id,
               case when exists (
                 select 1 from public.support_requests x
                 where x.thread_id = t.id and x.direction = 'inbound' and x.source <> 'web'
               ) then (select u.id from auth.users u where lower(u.email) = lower(t.email) limit 1) end),
      r.email, r.name, r.category, r.subject, r.message, r.source,
      coalesce(r.direction, 'inbound'), r.created_at,
      r.reported_profile_id,
      reported.first_name,
      t.email, r.sender_proof
    from threads t
    join public.support_requests r on r.thread_id = t.id
    left join public.profiles reported on reported.id = r.reported_profile_id
    order by t.last_message_at desc, t.id, r.seq desc;
end;
$$;

revoke all on function public.admin_support_requests(text, integer) from public, anon;
grant execute on function public.admin_support_requests(text, integer) to authenticated;
