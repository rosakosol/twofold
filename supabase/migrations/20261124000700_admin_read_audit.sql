-- The console's bulk reads leave a trail, are limited per admin, and the log can be read by actor
-- (security review, F8).
--
-- Only single-account views and actions were logged. A compromised support admin could page every
-- email out of admin_list_accounts, read 200 conversations at a time including abuse reports, and
-- download attachments, and none of it showed. Now:
--
--   * Each console read that returns other people's data writes a `read.*` audit row: what was
--     asked for and how many rows came back, never the content.
--   * Those reads share a limit of 300 an hour and 1,500 a day per admin. Normal use is a page load
--     or two a minute at most. Past it, reads fail with `admin_read_limit` until the hour turns.
--     To change it, replace private.admin_read_guard in a new migration.
--   * The search box (admin_lookup_account) counts against the limit, but is still not logged per
--     keystroke (see 20261109000800).
--   * admin_open_attachment logs each download, by attachment.
--   * admin_audit_recent shows the log by actor, or all of it, including rows with no subject,
--     which admin_audit_for_subject never shows.
--   * The log refuses UPDATE, DELETE and TRUNCATE by trigger. Grants already kept the app's roles
--     out; this stops the owner by accident. Removing the trigger is deliberate, and in the log of
--     migrations.
--
-- The functions are wrapped rather than rewritten: each original moves to `private` under a
-- `_unlogged` name with its body untouched, and a public function of the same name and signature
-- logs and calls it. Callers do not change.
--
-- Not done here: an alert on volume and a copy of the log off-site. Both need somewhere outside the
-- database to send to.

-- ---------------------------------------------------------------------------
-- The guard every wrapped read calls
-- ---------------------------------------------------------------------------

create or replace function private.admin_read_guard(
  p_action text,
  p_subject uuid default null,
  p_details jsonb default null,
  p_log boolean default true
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.consume_rate_limit('admin_read_hour', 300, interval '1 hour') where not allowed)
     or exists (select 1 from public.consume_rate_limit('admin_read_day', 1500, interval '1 day') where not allowed) then
    raise exception 'admin_read_limit' using errcode = 'P0001',
      hint = 'Too many console reads in the last hour. Try again later.';
  end if;
  if p_log then
    insert into private.admin_audit_log (actor_id, action, subject_profile_id, details)
    values (auth.uid(), p_action, p_subject, p_details);
  end if;
end;
$$;

revoke all on function private.admin_read_guard(text, uuid, jsonb, boolean) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Move the originals out of reach
-- ---------------------------------------------------------------------------

alter function public.admin_list_accounts(integer, integer) set schema private;
alter function private.admin_list_accounts(integer, integer) rename to admin_list_accounts_unlogged;

alter function public.admin_lookup_account(text) set schema private;
alter function private.admin_lookup_account(text) rename to admin_lookup_account_unlogged;

alter function public.admin_support_requests(text, integer) set schema private;
alter function private.admin_support_requests(text, integer) rename to admin_support_requests_unlogged;

alter function public.admin_reported_accounts(integer) set schema private;
alter function private.admin_reported_accounts(integer) rename to admin_reported_accounts_unlogged;

alter function public.admin_reports_about(uuid) set schema private;
alter function private.admin_reports_about(uuid) rename to admin_reports_about_unlogged;

alter function public.admin_most_blocked(integer, integer) set schema private;
alter function private.admin_most_blocked(integer, integer) rename to admin_most_blocked_unlogged;

alter function public.admin_thread_attachments(uuid) set schema private;
alter function private.admin_thread_attachments(uuid) rename to admin_thread_attachments_unlogged;

revoke all on function private.admin_list_accounts_unlogged(integer, integer) from public, anon, authenticated;
revoke all on function private.admin_lookup_account_unlogged(text) from public, anon, authenticated;
revoke all on function private.admin_support_requests_unlogged(text, integer) from public, anon, authenticated;
revoke all on function private.admin_reported_accounts_unlogged(integer) from public, anon, authenticated;
revoke all on function private.admin_reports_about_unlogged(uuid) from public, anon, authenticated;
revoke all on function private.admin_most_blocked_unlogged(integer, integer) from public, anon, authenticated;
revoke all on function private.admin_thread_attachments_unlogged(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- The wrappers. Each checks the role itself (as every admin_ function must, see
-- admin_audit_forgery_test), reads, then counts and logs what came back.
-- ---------------------------------------------------------------------------

create function public.admin_list_accounts(p_limit integer default 20, p_offset integer default 0)
returns table (
  profile_id uuid, email text, first_name text, created_at timestamptz, last_active_at timestamptz,
  subscription_tier text, subscription_active boolean, has_partner boolean, deleted_at timestamptz,
  total_count bigint
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_rows bigint;
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;
  return query select * from private.admin_list_accounts_unlogged(p_limit, p_offset);
  get diagnostics v_rows = row_count;
  perform private.admin_read_guard('read.accounts', null,
    jsonb_build_object('limit', p_limit, 'offset', p_offset, 'rows', v_rows));
end;
$$;

create function public.admin_lookup_account(p_query text)
returns table (
  profile_id uuid, email text, first_name text, created_at timestamptz, last_active_at timestamptz,
  subscription_tier text, subscription_active boolean, has_partner boolean, deleted_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;
  return query select * from private.admin_lookup_account_unlogged(p_query);
  perform private.admin_read_guard('read.lookup', null, null, false);
end;
$$;

create function public.admin_support_requests(p_status text default 'open', p_limit integer default 100)
returns table (
  id uuid, thread_id uuid, thread_token text, thread_size bigint, thread_position bigint,
  thread_last_at timestamptz, thread_status text, thread_handler_note text, thread_handled_at timestamptz,
  profile_id uuid, matched_profile_id uuid, email text, name text, category text, subject text,
  message text, source text, direction text, created_at timestamptz,
  reported_profile_id uuid, reported_name text,
  thread_email text, sender_proof text
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_rows bigint;
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;
  return query select * from private.admin_support_requests_unlogged(p_status, p_limit);
  get diagnostics v_rows = row_count;
  perform private.admin_read_guard('read.support_queue', null,
    jsonb_build_object('status', p_status, 'limit', p_limit, 'rows', v_rows));
end;
$$;

create function public.admin_reported_accounts(p_limit integer default 1000)
returns table (
  profile_id uuid, email text, first_name text, deleted_at timestamptz, report_count integer,
  reporter_count integer, block_notice_count integer, open_report_count integer,
  first_reported_at timestamptz, last_reported_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_rows bigint;
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;
  return query select * from private.admin_reported_accounts_unlogged(p_limit);
  get diagnostics v_rows = row_count;
  perform private.admin_read_guard('read.reported_accounts', null,
    jsonb_build_object('limit', p_limit, 'rows', v_rows));
end;
$$;

create function public.admin_reports_about(p_profile_id uuid)
returns table (
  request_id uuid, thread_id uuid, created_at timestamptz, is_block_notice boolean,
  report_surface text, subject text, message text, source text, reporter_id uuid,
  reporter_first_name text, reporter_email text, reporter_deleted_at timestamptz,
  thread_status text, thread_handled_at timestamptz, thread_handler_note text
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_rows bigint;
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;
  return query select * from private.admin_reports_about_unlogged(p_profile_id);
  get diagnostics v_rows = row_count;
  perform private.admin_read_guard('read.reports_about', p_profile_id, jsonb_build_object('rows', v_rows));
end;
$$;

create function public.admin_most_blocked(p_min_blocks integer default 2, p_limit integer default 50)
returns table (
  profile_id uuid, email text, first_name text, blocked_by_count bigint, most_recent timestamptz
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_rows bigint;
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;
  return query select * from private.admin_most_blocked_unlogged(p_min_blocks, p_limit);
  get diagnostics v_rows = row_count;
  perform private.admin_read_guard('read.most_blocked', null,
    jsonb_build_object('min_blocks', p_min_blocks, 'limit', p_limit, 'rows', v_rows));
end;
$$;

-- The list of a conversation's attachments: names and sizes, not the files. Counted, and logged by
-- conversation.
create function public.admin_thread_attachments(p_thread_id uuid)
returns table (
  id uuid, request_id uuid, filename text, content_type text, size_bytes bigint,
  r2_key text, direction text, created_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_rows bigint;
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;
  return query select * from private.admin_thread_attachments_unlogged(p_thread_id);
  get diagnostics v_rows = row_count;
  perform private.admin_read_guard('read.attachment_list', null,
    jsonb_build_object('thread_id', p_thread_id, 'rows', v_rows));
end;
$$;

-- One attachment, to download. Its own row, because opening a file is the read that matters.
create function public.admin_open_attachment(p_thread_id uuid, p_attachment_id uuid)
returns table (r2_key text, filename text)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_key text;
  v_name text;
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;
  select a.r2_key, a.filename into v_key, v_name
  from private.admin_thread_attachments_unlogged(p_thread_id) a
  where a.id = p_attachment_id;
  if v_key is null then
    return;
  end if;
  perform private.admin_read_guard('read.attachment', null,
    jsonb_build_object('thread_id', p_thread_id, 'attachment_id', p_attachment_id));
  r2_key := v_key;
  filename := v_name;
  return next;
end;
$$;

revoke all on function public.admin_list_accounts(integer, integer) from public, anon;
revoke all on function public.admin_lookup_account(text) from public, anon;
revoke all on function public.admin_support_requests(text, integer) from public, anon;
revoke all on function public.admin_reported_accounts(integer) from public, anon;
revoke all on function public.admin_reports_about(uuid) from public, anon;
revoke all on function public.admin_most_blocked(integer, integer) from public, anon;
revoke all on function public.admin_thread_attachments(uuid) from public, anon;
revoke all on function public.admin_open_attachment(uuid, uuid) from public, anon;
grant execute on function public.admin_list_accounts(integer, integer) to authenticated;
grant execute on function public.admin_lookup_account(text) to authenticated;
grant execute on function public.admin_support_requests(text, integer) to authenticated;
grant execute on function public.admin_reported_accounts(integer) to authenticated;
grant execute on function public.admin_reports_about(uuid) to authenticated;
grant execute on function public.admin_most_blocked(integer, integer) to authenticated;
grant execute on function public.admin_thread_attachments(uuid) to authenticated;
grant execute on function public.admin_open_attachment(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Reading the log by actor
-- ---------------------------------------------------------------------------

create or replace function public.admin_audit_recent(p_actor uuid default null, p_limit integer default 200)
returns table (
  actor_id uuid, actor_email text, action text, subject_profile_id uuid, subject_email text,
  reason text, details jsonb, occurred_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;
  return query
    select l.actor_id, actor.email::text, l.action, l.subject_profile_id, subject.email::text,
           l.reason, l.details, l.occurred_at
    from private.admin_audit_log l
    left join auth.users actor on actor.id = l.actor_id
    left join auth.users subject on subject.id = l.subject_profile_id
    where p_actor is null or l.actor_id = p_actor
    order by l.occurred_at desc, l.id desc
    limit least(greatest(coalesce(p_limit, 200), 1), 500);
end;
$$;

revoke all on function public.admin_audit_recent(uuid, integer) from public, anon;
grant execute on function public.admin_audit_recent(uuid, integer) to authenticated;

create index if not exists admin_audit_log_actor_idx
  on private.admin_audit_log (actor_id, occurred_at desc);

-- ---------------------------------------------------------------------------
-- Append-only, by trigger as well as by grant
-- ---------------------------------------------------------------------------

create or replace function private.admin_audit_log_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'the admin audit log is append-only' using errcode = '42501';
end;
$$;

drop trigger if exists admin_audit_log_no_change on private.admin_audit_log;
create trigger admin_audit_log_no_change
  before update or delete on private.admin_audit_log
  for each row execute function private.admin_audit_log_append_only();

drop trigger if exists admin_audit_log_no_truncate on private.admin_audit_log;
create trigger admin_audit_log_no_truncate
  before truncate on private.admin_audit_log
  for each statement execute function private.admin_audit_log_append_only();
