-- ============================================================
-- How often an account has been reported, when, and by whom
-- ============================================================
--
-- 20261113001100 started storing who an abuse report is about (support_requests.reported_profile_id),
-- and the console reads it one report at a time: admin_report_context, beside an open conversation.
-- What there was no way to ask is the other direction. Starting from an account, how many times has
-- this person been reported, by whom, and when. That is the question an account page needs answered
-- before anybody decides to delete it.
--
-- Two reads, both support-only, both security definer because support_requests has RLS on with no
-- policies at all (20261109001100): nobody reads it except through is_support_admin()-gated functions.
--
--   admin_reported_accounts()       one row per reported account, with counts. The users list and
--                                   Moderation read it. Names and counts, no reporter identities.
--   admin_reports_about(profile)    every report naming one account: when, who sent it, from where,
--                                   what they wrote, and where the conversation stands.
--
-- ---------------------------------------------------------------------------
-- Reports and block notices are counted apart
-- ---------------------------------------------------------------------------
--
-- submit-help-message files the notice the app sends after a block as a "Report Abuse" request
-- naming the blocked person, with a subject composed server-side as "[Blocked] <name>"
-- (block-notice.ts). It is not somebody reporting anyone: it is somebody using the block button,
-- which blocked_profiles already counts. So "reported 3 times" must not quietly mean "reported once
-- and blocked twice". The subject prefix is the only marker the row carries; there is no kind column.
-- A reporter who typed "[Blocked]" at the start of their own subject would be counted as a block
-- notice. The app's report form does not offer that field to edit in a way that makes it likely.
--
-- ---------------------------------------------------------------------------
-- Not audited
-- ---------------------------------------------------------------------------
--
-- admin_report_context records 'report.view' because opening a report is the moment a reported
-- account is looked up. admin_reports_about is read by the account page, which already records the
-- view through admin_account_detail, and a second row for the same page load would halve how much
-- history the page's "Admin history" panel shows. admin_reported_accounts says who has been
-- reported, not who anybody is, the same footing as admin_most_blocked, which is not audited either.
--
-- No foreign keys are followed with inner joins: the reporter's or the reported person's profile can
-- be soft-deleted and scrubbed, and a report has to keep showing when either has gone.

create or replace function public.admin_reported_accounts(p_limit integer default 1000)
returns table (
  profile_id uuid,
  email text,
  first_name text,
  deleted_at timestamptz,
  report_count integer,
  reporter_count integer,
  block_notice_count integer,
  open_report_count integer,
  first_reported_at timestamptz,
  last_reported_at timestamptz
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
    with tagged as (
      select
        r.reported_profile_id,
        r.profile_id as reporter_id,
        r.created_at,
        coalesce(r.subject, '') like '[Blocked] %' as is_block_notice,
        t.status as thread_status
      from public.support_requests r
      left join public.support_threads t on t.id = r.thread_id
      where r.reported_profile_id is not null
    ),
    counted as (
      select
        g.reported_profile_id,
        (count(*) filter (where not g.is_block_notice))::int as report_count,
        (count(distinct g.reporter_id) filter (where not g.is_block_notice))::int as reporter_count,
        (count(*) filter (where g.is_block_notice))::int as block_notice_count,
        (count(*) filter (where not g.is_block_notice and g.thread_status = 'open'))::int as open_report_count,
        min(g.created_at) filter (where not g.is_block_notice) as first_reported_at,
        max(g.created_at) filter (where not g.is_block_notice) as last_reported_at,
        max(g.created_at) as last_any_at
      from tagged g
      group by g.reported_profile_id
    )
    select
      c.reported_profile_id,
      u.email::text,
      p.first_name,
      coalesce(p.account_deleted_at, u.deleted_at),
      c.report_count,
      c.reporter_count,
      c.block_notice_count,
      c.open_report_count,
      c.first_reported_at,
      c.last_reported_at
    from counted c
    left join public.profiles p on p.id = c.reported_profile_id
    left join auth.users u on u.id = c.reported_profile_id
    order by c.report_count desc, c.reporter_count desc, c.last_any_at desc
    limit least(greatest(coalesce(p_limit, 1000), 1), 5000);
end;
$$;

revoke all on function public.admin_reported_accounts(integer) from public, anon;
grant execute on function public.admin_reported_accounts(integer) to authenticated;

-- ---------------------------------------------------------------------------

create or replace function public.admin_reports_about(p_profile_id uuid)
returns table (
  request_id uuid,
  thread_id uuid,
  created_at timestamptz,
  is_block_notice boolean,
  report_surface text,
  subject text,
  message text,
  source text,
  reporter_id uuid,
  reporter_first_name text,
  reporter_email text,
  reporter_deleted_at timestamptz,
  thread_status text,
  thread_handled_at timestamptz,
  thread_handler_note text
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

  if p_profile_id is null then
    return;
  end if;

  return query
    select
      r.id,
      r.thread_id,
      r.created_at,
      coalesce(r.subject, '') like '[Blocked] %',
      r.report_surface,
      r.subject,
      r.message,
      r.source,
      r.profile_id,
      p.first_name,
      -- A live reporter's address as it is now; a deleted one's as it was when they reported. Soft
      -- deletion obfuscates auth.users.email, and support_requests is never scrubbed because it has
      -- to outlive the account, so the stored address is the one that still means something.
      case
        when coalesce(p.account_deleted_at, u.deleted_at) is not null then coalesce(r.email, u.email::text)
        else coalesce(u.email::text, r.email)
      end,
      coalesce(p.account_deleted_at, u.deleted_at),
      t.status,
      t.handled_at,
      t.handler_note
    from public.support_requests r
    left join public.support_threads t on t.id = r.thread_id
    left join public.profiles p on p.id = r.profile_id
    left join auth.users u on u.id = r.profile_id
    where r.reported_profile_id = p_profile_id
    order by r.created_at desc
    limit 500;
end;
$$;

revoke all on function public.admin_reports_about(uuid) from public, anon;
grant execute on function public.admin_reports_about(uuid) to authenticated;
