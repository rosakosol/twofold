-- ---------------------------------------------------------------------------
-- Looking someone up, so support stops being a SQL prompt
-- ---------------------------------------------------------------------------
--
-- People write in asking to have their account deleted, their subscription sorted out, their
-- partner disconnected. Answering any of those starts with finding them, and the only key they
-- ever supply is an email address — which lives in `auth.users`, a schema PostgREST does not serve
-- at all. So today that question is answered by opening a SQL editor against production, which is
-- a tool with no audit trail, no read-only mode and no way to be wrong quietly.
--
-- Two security-definer functions replace it. Both check `is_support_admin()` on entry — the role
-- that exists precisely so that touching personal data is a narrower grant than editing a trivia
-- deck.
--
-- ---------------------------------------------------------------------------
-- What these deliberately do NOT return
-- ---------------------------------------------------------------------------
--
-- Status and structure. Never content.
--
-- No memories, no photos, no daily-question answers, no game responses, no boarding passes, no
-- live positions. None of the tickets this exists to answer requires reading a couple's journal,
-- and a support console that can is a liability whose only protection is that nobody chose to.
-- `flight_documents` in particular carries boarding passes — full legal names, PNRs, frequent-flyer
-- numbers — and on many airline sites a PNR plus a surname is enough to change somebody's booking.
--
-- Flights are counted, never listed, and that is not squeamishness either: `flights.shared = false`
-- means "my partner cannot see this flight", the privacy policy lists it under things that stay
-- private to you, and `flight_privacy_test` spends twenty-one assertions enforcing it. A support
-- screen listing those rows would break a specific written promise to the person least able to
-- absorb it — the set of people who hide a flight includes people leaving a relationship that is
-- not safe. A count tells you tracking works; a list tells you where somebody is.
--
-- ---------------------------------------------------------------------------
-- The audit log
-- ---------------------------------------------------------------------------
--
-- `admin_account_detail` writes a row every time it runs. That is the call that turns an email
-- address into a person's subscription, partner and history, so it is the one worth recording.
-- `admin_lookup_account` does not: it is the search box, it returns only what is needed to pick
-- the right row, and logging every keystroke-driven query would bury the reads that matter.
--
-- `reason` is nullable here and will not be on the action functions. Requiring a typed
-- justification before you may look at the account somebody just emailed about is friction against
-- the normal case; requiring one before deleting their account is not.

create table if not exists private.admin_audit_log (
  id bigint generated always as identity primary key,
  -- No foreign key, deliberately: the log has to outlive both parties. A cascade from `profiles`
  -- would erase the record of an account's deletion at the moment it was deleted, which is exactly
  -- the row anybody would later want. Same reasoning as `subscription_events`.
  actor_id uuid not null,
  action text not null,
  subject_profile_id uuid,
  reason text,
  -- Before/after, ids acted on, counts — whatever the action needs to be explicable in two years.
  -- Never content, on the same rule as the functions above.
  details jsonb,
  occurred_at timestamptz not null default now()
);

comment on table private.admin_audit_log is
  'Append-only record of admin access to, and action on, another person''s account. In `private` '
  'so it is unreachable over PostgREST; a log of who looked at whom is itself sensitive, and is '
  'read through an is_support_admin()-gated function like everything else here.';

create index if not exists admin_audit_log_subject_idx
  on private.admin_audit_log (subject_profile_id, occurred_at desc);

create index if not exists admin_audit_log_occurred_idx
  on private.admin_audit_log (occurred_at desc);

-- Writes go through the definer functions below, which run as owner. Nothing else may touch it —
-- and there is no update or delete path at all, by design: a log somebody can tidy is not a log.
revoke all on private.admin_audit_log from public, anon, authenticated;

create or replace function private.record_admin_action(
  p_action text,
  p_subject uuid default null,
  p_reason text default null,
  p_details jsonb default null
)
returns void
language sql
security definer
set search_path = private, public
as $$
  insert into private.admin_audit_log (actor_id, action, subject_profile_id, reason, details)
  values (auth.uid(), p_action, p_subject, p_reason, p_details);
$$;

revoke all on function private.record_admin_action(text, uuid, text, jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- The search box
-- ---------------------------------------------------------------------------
--
-- One input, three kinds of key, because the person on the other end of a support email supplies
-- whichever they happen to have: their email address, a profile id copied from a previous thread,
-- or the invite code they were trying to redeem when it went wrong.
--
-- Email matches exactly, lowercased, rather than by prefix or similarity. A fuzzy match here is a
-- browsing tool, and browsing is not what this is for.

create or replace function public.admin_lookup_account(p_query text)
returns table (
  profile_id uuid,
  email text,
  first_name text,
  created_at timestamptz,
  last_active_at timestamptz,
  subscription_tier text,
  subscription_active boolean,
  has_partner boolean,
  deleted_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_query text := trim(coalesce(p_query, ''));
  v_uuid uuid;
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;
  if v_query = '' then
    return;
  end if;

  -- A profile id pasted from an earlier thread. Parsed rather than cast, so a query that merely
  -- looks uuid-ish does not error the whole search.
  begin
    v_uuid := v_query::uuid;
  exception when others then
    v_uuid := null;
  end;

  return query
    select
      p.id,
      u.email::text,
      p.first_name,
      p.created_at,
      p.last_active_at,
      p.subscription_tier,
      p.subscription_active,
      exists (
        select 1 from public.couples c
        where c.status = 'active' and (c.partner_a_id = p.id or c.partner_b_id = p.id)
      ),
      -- `delete_own_account` soft-deletes: auth.users keeps the row with deleted_at set, because a
      -- hard delete would cascade through profiles and take the other partner's shared history
      -- with it. So a deleted account still appears here, correctly, and says so.
      u.deleted_at
    from public.profiles p
    join auth.users u on u.id = p.id
    where
      (v_uuid is not null and p.id = v_uuid)
      or lower(u.email) = lower(v_query)
      or exists (
        select 1 from public.invite_codes ic
        where upper(ic.code) = upper(v_query) and ic.inviter_id = p.id
      )
    order by p.created_at desc
    limit 25;
end;
$$;

-- ---------------------------------------------------------------------------
-- One account, in full
-- ---------------------------------------------------------------------------
--
-- Returns jsonb rather than a wide row. The shape grows every time support needs one more fact,
-- and a `returns table` with thirty columns makes each addition a signature change that every
-- caller must be redeployed for.
--
-- Volatile, not stable, because it writes the audit row.

create or replace function public.admin_account_detail(
  p_profile_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_result jsonb;
  v_couple public.couples;
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;

  select * into v_couple
  from public.couples
  where status = 'active'
    and (partner_a_id = p_profile_id or partner_b_id = p_profile_id);

  select jsonb_build_object(
    'profile', jsonb_build_object(
      'id', p.id,
      'first_name', p.first_name,
      'created_at', p.created_at,
      'last_active_at', p.last_active_at,
      'onboarding_completed_at', p.onboarding_completed_at,
      'dormancy_warned_at', p.dormancy_warned_at,
      'timezone', p.timezone,
      'locale', p.locale
    ),
    'auth', jsonb_build_object(
      'email', u.email,
      'email_confirmed_at', u.email_confirmed_at,
      'last_sign_in_at', u.last_sign_in_at,
      -- Set by delete-account's soft delete. Sign-in is permanently disabled; the row remains so
      -- the FK cascade never fires and the other partner's history survives.
      'deleted_at', u.deleted_at,
      'providers', (
        select coalesce(jsonb_agg(distinct i.provider), '[]'::jsonb)
        from auth.identities i where i.user_id = u.id
      )
    ),
    'subscription', jsonb_build_object(
      'active', p.subscription_active,
      'tier', p.subscription_tier,
      -- Decides what can be offered: an App Store subscription is not ours to cancel. Null means
      -- the webhook has not seen this account since the column was added, and must read as
      -- "unknown" rather than as anything about the subscription.
      'store', p.subscription_store,
      'will_renew', p.subscription_will_renew,
      'started_at', p.subscription_started_at,
      'checked_at', p.subscription_checked_at
    ),
    'couple', case when v_couple.id is null then null else jsonb_build_object(
      'id', v_couple.id,
      'started_dating_on', v_couple.started_dating_on,
      'created_at', v_couple.created_at,
      'partner_id', case when v_couple.partner_a_id = p_profile_id
        then v_couple.partner_b_id else v_couple.partner_a_id end,
      'partner_first_name', (
        select pp.first_name from public.profiles pp
        where pp.id = case when v_couple.partner_a_id = p_profile_id
          then v_couple.partner_b_id else v_couple.partner_a_id end
      ),
      'partner_email', (
        select uu.email from auth.users uu
        where uu.id = case when v_couple.partner_a_id = p_profile_id
          then v_couple.partner_b_id else v_couple.partner_a_id end
      )
    ) end,
    'counts', jsonb_build_object(
      -- Counted, never listed. See this migration's header: `flights.shared = false` is a promise
      -- kept to people for whom it sometimes matters a great deal, and a count answers every
      -- support question a list would.
      'flights_tracked', (
        select count(*) from public.flights f
        where f.couple_id = v_couple.id
      ),
      'flights_tracking_enabled', (
        select count(*) from public.flights f
        where f.couple_id = v_couple.id and f.tracking_enabled
      ),
      'trips', (select count(*) from public.trips t where t.couple_id = v_couple.id),
      'memories', (select count(*) from public.memories m where m.couple_id = v_couple.id),
      'blocked_by_them', (select count(*) from public.blocked_profiles b where b.blocker_id = p_profile_id),
      'blocking_them', (select count(*) from public.blocked_profiles b where b.blocked_id = p_profile_id)
    ),
    'credits', jsonb_build_object(
      'streak_repair_unused', (
        select count(*) from public.streak_repair_credits c
        where c.profile_id = p_profile_id and c.consumed_at is null
      ),
      'record_export_unused', (
        select count(*) from public.record_export_credits c
        where c.profile_id = p_profile_id and c.consumed_at is null
      )
    ),
    -- Composed from the same three helpers `public.flight_allowance` uses, rather than by calling
    -- it. That function gates on `is_couple_member(auth.uid())` and raises 42501 for anybody else
    -- — correctly, since it is the app's own endpoint — so a support admin calling it gets an
    -- error rather than an answer. The parts underneath are couple-scoped arguments with no
    -- caller check, which is what this needs.
    'flight_allowance', case when v_couple.id is null then null else jsonb_build_object(
      'tier', private.couple_effective_tier(v_couple.id),
      'limit', private.flight_limit_for_couple(v_couple.id),
      'used', public.flights_used_this_month(v_couple.id)
    ) end
  )
  into v_result
  from public.profiles p
  join auth.users u on u.id = p.id
  where p.id = p_profile_id;

  if v_result is null then
    return null;
  end if;

  -- The call that turns an email address into a person. Recorded before returning, so a read that
  -- happened is logged even if the caller never renders it.
  perform private.record_admin_action(
    'account.view', p_profile_id, p_reason,
    jsonb_build_object('had_couple', v_couple.id is not null)
  );

  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- Reading the log
-- ---------------------------------------------------------------------------

create or replace function public.admin_audit_for_subject(p_profile_id uuid, p_limit integer default 50)
returns table (
  actor_id uuid,
  actor_email text,
  action text,
  reason text,
  details jsonb,
  occurred_at timestamptz
)
language plpgsql
stable
security definer
set search_path = private, public, auth
as $$
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;

  return query
    select l.actor_id, u.email::text, l.action, l.reason, l.details, l.occurred_at
    from private.admin_audit_log l
    left join auth.users u on u.id = l.actor_id
    where l.subject_profile_id = p_profile_id
    order by l.occurred_at desc
    limit least(greatest(coalesce(p_limit, 50), 1), 500);
end;
$$;

revoke execute on function public.admin_lookup_account(text) from anon;
revoke execute on function public.admin_account_detail(uuid, text) from anon;
revoke execute on function public.admin_audit_for_subject(uuid, integer) from anon;

grant execute on function public.admin_lookup_account(text) to authenticated;
grant execute on function public.admin_account_detail(uuid, text) to authenticated;
grant execute on function public.admin_audit_for_subject(uuid, integer) to authenticated;
