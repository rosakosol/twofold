-- ---------------------------------------------------------------------------
-- Making somebody whole, and noticing an account people keep blocking
-- ---------------------------------------------------------------------------
--
-- The remainder of the support console. Nothing here is destructive; all of it is the kind of
-- thing currently done by hand in a SQL editor, which is to say with no reason recorded and no
-- trace that it happened.
--
-- ---------------------------------------------------------------------------
-- Grants carry a synthetic transaction id, and that is on purpose
-- ---------------------------------------------------------------------------
--
-- `streak_repair_credits.transaction_id` and `record_export_credits.transaction_id` are NOT NULL
-- and UNIQUE, because they are the store transaction a purchase arrived on and that uniqueness is
-- what makes RevenueCat redelivering an event harmless.
--
-- An admin grant has no store transaction. It gets `admin:<uuid>`, which satisfies the constraint
-- and does something better besides: a comped credit is now distinguishable from a bought one by
-- looking at the row. Anybody later asking "how many of these did we give away" can answer it, and
-- a refund reconciliation that assumed every credit had a payment behind it would otherwise be
-- quietly wrong.

create or replace function public.admin_grant_streak_repair(p_profile_id uuid, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = private, public
as $$
declare
  v_transaction_id text := 'admin:' || gen_random_uuid()::text;
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'a reason is required' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = p_profile_id) then
    raise exception 'no such account';
  end if;

  insert into public.streak_repair_credits (profile_id, transaction_id)
  values (p_profile_id, v_transaction_id);

  perform private.record_admin_action(
    'grant.streak_repair', p_profile_id, p_reason,
    jsonb_build_object('transaction_id', v_transaction_id)
  );

  return p_profile_id;
end;
$$;

create or replace function public.admin_grant_record_export(p_profile_id uuid, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = private, public
as $$
declare
  v_transaction_id text := 'admin:' || gen_random_uuid()::text;
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'a reason is required' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = p_profile_id) then
    raise exception 'no such account';
  end if;

  insert into public.record_export_credits (profile_id, transaction_id)
  values (p_profile_id, v_transaction_id);

  perform private.record_admin_action(
    'grant.record_export', p_profile_id, p_reason,
    jsonb_build_object('transaction_id', v_transaction_id)
  );

  return p_profile_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Flight limit overrides
-- ---------------------------------------------------------------------------
--
-- `private.flight_limit_overrides` decides how much AeroAPI money an account may spend, which is
-- why it lives in `private` and has never been reachable from anywhere but a SQL prompt. That is
-- also why every write here is audited twice over: in `admin_audit_log`, and in the table's own
-- `note` column, whose existing comment says the quiet part — "an unexplained override found in
-- two years' time is indistinguishable from a mistake, and nobody will dare delete it."
--
-- A null limit removes the override rather than setting one, because "put this account back to
-- normal" is a thing support will need and deleting a row from `private` by hand is exactly what
-- this replaces.

create or replace function public.admin_set_flight_limit(
  p_profile_id uuid,
  p_monthly_limit integer,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = private, public
as $$
declare
  v_previous integer;
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'a reason is required' using errcode = '22023';
  end if;
  if p_monthly_limit is not null and p_monthly_limit < 0 then
    raise exception 'a limit cannot be negative' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = p_profile_id) then
    raise exception 'no such account';
  end if;

  select monthly_limit into v_previous
  from private.flight_limit_overrides where profile_id = p_profile_id;

  if p_monthly_limit is null then
    delete from private.flight_limit_overrides where profile_id = p_profile_id;
  else
    insert into private.flight_limit_overrides (profile_id, monthly_limit, note)
    values (p_profile_id, p_monthly_limit, p_reason)
    on conflict (profile_id) do update
      set monthly_limit = excluded.monthly_limit, note = excluded.note;
  end if;

  perform private.record_admin_action(
    'flight_limit.set', p_profile_id, p_reason,
    jsonb_build_object('previous', v_previous, 'new', p_monthly_limit)
  );
end;
$$;

create or replace function public.admin_flight_limit_override(p_profile_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = private, public
as $$
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;

  return (
    select jsonb_build_object('monthly_limit', o.monthly_limit, 'note', o.note, 'created_at', o.created_at)
    from private.flight_limit_overrides o
    where o.profile_id = p_profile_id
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Accounts other people keep blocking
-- ---------------------------------------------------------------------------
--
-- Deliberately a ranking, not a list of who blocked whom.
--
-- The safety signal worth having is "several unrelated people have blocked this account", which is
-- what turns one person's abuse report into something with corroboration. A browsable list of
-- every block would be a graph of who dislikes whom across the whole app, which answers no support
-- question and would sit in a console where somebody could read it for no reason.
--
-- Blocking is deliberately invisible to the blocked party in the app — `DisconnectPartnerView`
-- says "They aren't told" — and nothing here changes that.
--
-- Abuse REPORTS are not in this database at all: `submit-help-message` emails them to the support
-- inbox. So there is no report view to build until those submissions are captured as rows, which
-- is its own piece of work.

create or replace function public.admin_most_blocked(p_min_blocks integer default 2, p_limit integer default 50)
returns table (
  profile_id uuid,
  email text,
  first_name text,
  blocked_by_count bigint,
  most_recent timestamptz
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
    select b.blocked_id, u.email::text, p.first_name, count(*)::bigint, max(b.created_at)
    from public.blocked_profiles b
    join public.profiles p on p.id = b.blocked_id
    join auth.users u on u.id = b.blocked_id
    group by b.blocked_id, u.email, p.first_name
    having count(*) >= greatest(coalesce(p_min_blocks, 2), 1)
    order by count(*) desc, max(b.created_at) desc
    limit least(greatest(coalesce(p_limit, 50), 1), 200);
end;
$$;

revoke execute on function public.admin_grant_streak_repair(uuid, text) from anon;
revoke execute on function public.admin_grant_record_export(uuid, text) from anon;
revoke execute on function public.admin_set_flight_limit(uuid, integer, text) from anon;
revoke execute on function public.admin_flight_limit_override(uuid) from anon;
revoke execute on function public.admin_most_blocked(integer, integer) from anon;

grant execute on function public.admin_grant_streak_repair(uuid, text) to authenticated;
grant execute on function public.admin_grant_record_export(uuid, text) to authenticated;
grant execute on function public.admin_set_flight_limit(uuid, integer, text) to authenticated;
grant execute on function public.admin_flight_limit_override(uuid) to authenticated;
grant execute on function public.admin_most_blocked(integer, integer) to authenticated;
