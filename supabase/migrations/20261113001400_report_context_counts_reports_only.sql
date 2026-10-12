-- ---------------------------------------------------------------------------
-- The report panel's counts leave block notices out
-- ---------------------------------------------------------------------------
--
-- Blocking someone files a "[Blocked] <name>" notice as a Report Abuse request
-- (submit-help-message), so admin_report_context counted every block as a report too. Block
-- notices are a separate thing from reports: the account page and Moderation
-- (20261113001300) already count them apart, and blocks have their own column here
-- (blocked_by_count). times_reported and distinct_reporters now match them, using the same
-- subject test.
--
-- Unchanged otherwise: same signature, same gate, same audit entry.

create or replace function public.admin_report_context(p_request_id uuid)
returns table (
  reported_profile_id uuid,
  report_surface text,
  first_name text,
  email text,
  joined_at timestamptz,
  account_deleted_at timestamptz,
  times_reported integer,
  distinct_reporters integer,
  blocked_by_count integer,
  reporter_blocked_them boolean,
  are_partners boolean,
  were_partners boolean
)
language plpgsql
security definer
set search_path = private, public, auth
as $$
declare
  v_request public.support_requests;
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;

  select * into v_request from public.support_requests where id = p_request_id;
  if not found or v_request.reported_profile_id is null then
    return;
  end if;

  perform private.record_admin_action(
    'report.view', v_request.reported_profile_id, null, jsonb_build_object('request_id', p_request_id)
  );

  return query
  select
    v_request.reported_profile_id,
    v_request.report_surface,
    p.first_name,
    u.email::text,
    p.created_at,
    p.account_deleted_at,
    (select count(*)::int from public.support_requests r
      where r.reported_profile_id = v_request.reported_profile_id
        and coalesce(r.subject, '') not like '[Blocked] %'),
    (select count(distinct r.profile_id)::int from public.support_requests r
      where r.reported_profile_id = v_request.reported_profile_id
        and coalesce(r.subject, '') not like '[Blocked] %'),
    (select count(*)::int from public.blocked_profiles b where b.blocked_id = v_request.reported_profile_id),
    exists (select 1 from public.blocked_profiles b
      where b.blocker_id = v_request.profile_id and b.blocked_id = v_request.reported_profile_id),
    exists (select 1 from public.couples c
      where c.status = 'active'
        and ((c.partner_a_id = v_request.profile_id and c.partner_b_id = v_request.reported_profile_id)
          or (c.partner_b_id = v_request.profile_id and c.partner_a_id = v_request.reported_profile_id))),
    exists (select 1 from public.couples c
      where c.status = 'dissolved'
        and ((c.partner_a_id = v_request.profile_id and c.partner_b_id = v_request.reported_profile_id)
          or (c.partner_b_id = v_request.profile_id and c.partner_a_id = v_request.reported_profile_id)))
  from (select v_request.reported_profile_id as id) target
  left join public.profiles p on p.id = target.id
  left join auth.users u on u.id = target.id;
end;
$$;

revoke all on function public.admin_report_context(uuid) from public, anon;
grant execute on function public.admin_report_context(uuid) to authenticated;
