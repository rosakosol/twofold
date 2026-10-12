-- ============================================================
-- The inbox list says who a report is about
-- ============================================================
--
-- 20261113001100 stored who an abuse report names, and the console shows them once the
-- conversation is open. The list of conversations still showed only the reporter, so finding "the
-- report about Rex" meant opening reports one at a time. Each row now carries the reported account's
-- id and first name, which is what the list shows and what its abuse-report filter keys on.
--
-- The first name only. The rest (email, history, blocks) stays behind admin_report_context, which
-- records that it was looked at; a name in a list is what an inbox needs to be navigable.
--
-- Dropped and recreated because the return type grows. Same arguments, same grants.

drop function if exists public.admin_support_requests(text, integer);

create function public.admin_support_requests(
  p_status text default 'open',
  p_limit integer default 100
)
returns table (
  id uuid, thread_id uuid, thread_token text, thread_size bigint, thread_position bigint,
  thread_last_at timestamptz, thread_status text, thread_handler_note text, thread_handled_at timestamptz,
  profile_id uuid, matched_profile_id uuid, email text, name text, category text, subject text,
  message text, source text, direction text, created_at timestamptz,
  reported_profile_id uuid, reported_name text
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
      coalesce(t.profile_id, r.profile_id,
               (select u.id from auth.users u where lower(u.email) = lower(t.email) limit 1)),
      r.email, r.name, r.category, r.subject, r.message, r.source,
      coalesce(r.direction, 'inbound'), r.created_at,
      r.reported_profile_id,
      reported.first_name
    from threads t
    join public.support_requests r on r.thread_id = t.id
    left join public.profiles reported on reported.id = r.reported_profile_id
    order by t.last_message_at desc, t.id, r.seq desc;
end;
$$;

revoke execute on function public.admin_support_requests(text, integer) from public, anon;
grant execute on function public.admin_support_requests(text, integer) to authenticated;
