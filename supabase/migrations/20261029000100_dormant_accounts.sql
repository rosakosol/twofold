-- ---------------------------------------------------------------------------
-- Accounts nobody has opened for two years
-- ---------------------------------------------------------------------------
--
-- Twofold has never deleted an account it wasn't asked to. Shared archives expire on their 90-day
-- timer, but that timer only ever starts when somebody ends a connection — a couple who simply
-- stop opening the app leave their trips, memories, photos and answers here forever. That is a
-- retention policy of "indefinitely", which is not a policy, and it is the one thing the privacy
-- policy could not honestly describe.
--
-- So: two years with nobody signing in, and the accounts close.
--
-- ---------------------------------------------------------------------------
-- Inactivity, not lapsed payment
-- ---------------------------------------------------------------------------
--
-- The timer reads `last_active_at` and nothing else. It does not look at `subscription_active`.
--
-- A couple who stopped paying and still open the app keep everything, indefinitely, exactly as
-- 20261028000000 promises: their content is readable, exportable and deletable forever and only
-- adding to it needs a subscription. Deleting the archives of people who still turn up would turn
-- that promise into a threat, and "pay or we delete your memories" is not a business this should
-- be in. It is also the harder position to defend: storage limitation asks whether data is still
-- needed, and someone opening the app weekly plainly still needs it.
--
-- ---------------------------------------------------------------------------
-- Both of you, or neither
-- ---------------------------------------------------------------------------
--
-- Activity is measured per couple, not per person, and the couple's clock reads from whichever
-- partner was here most recently. One of you opening the app keeps both accounts and the whole
-- shared history alive.
--
-- The alternative — expiring each account on its own timer — would delete one half of a couple
-- out from under the other, dissolving a live connection and starting the archive clock on a
-- relationship that one of them is still actively using. A solo account with no active couple is
-- its own cohort of one.
--
-- ---------------------------------------------------------------------------
-- What closing actually does, and why it is not a second purge route
-- ---------------------------------------------------------------------------
--
-- 20261005000000 established one rule with some force: the 90-day archive timer is the only thing
-- that ever deletes shared content. Nothing else — not a request, not a partner, not support.
--
-- This does not break that. Closing a dormant couple does exactly what a partner leaving does:
-- dissolves the couple, which stamps the archive with its deletion date, and scrubs both profiles
-- the same way `delete_own_account` scrubs one. The shared content is then deleted by the same
-- timer as everything else, 90 days later. Total worst case is two years plus ninety days, which
-- is what the privacy policy should say, rather than inventing a second way for shared data to
-- disappear.
--
-- ---------------------------------------------------------------------------

alter table public.profiles
  add column if not exists dormancy_warned_at timestamptz;

comment on column public.profiles.dormancy_warned_at is
  'When the last dormancy warning was sent to this account. Compared against the stage boundary '
  'rather than against a stage number, so a warning sent in an earlier cycle is naturally ignored '
  'once activity pushes the boundaries forward — becoming active again resets the warnings without '
  'anything having to clear this column.';

-- ---------------------------------------------------------------------------
-- The one place the policy is written down
-- ---------------------------------------------------------------------------
--
-- Two years, warned at thirty days and again at seven. Kept as functions rather than inlined so
-- that the tests, the warning job and the purge job cannot drift apart on what "dormant" means.
create or replace function private.dormancy_period()
returns interval
language sql
immutable
as $$ select interval '24 months' $$;

comment on function private.dormancy_period() is
  'How long an account can go unopened before it is closed. Read by private.dormancy_cohort() and '
  'by the pgTAP tests, so there is exactly one definition of the policy.';

-- ---------------------------------------------------------------------------
-- Who is due for what
-- ---------------------------------------------------------------------------
--
-- Returns one row per profile that needs something done to it right now, with the stage saying
-- what.
--
-- In `public`, not `private`, and that is not a slip. The only caller is the purge job, which
-- reaches it through PostgREST as service role — and PostgREST can only see the schemas listed in
-- config.toml, which are `public` and `graphql_public`. A function like this in `private` is
-- simply unreachable, and the failure is silent at the call site. That exact mistake has shipped
-- here before: `grant_streak_repair_credit` lived in `private`, and every paid streak repair
-- failed quietly until 20261026000100 moved it.
--
-- Reachable is not the same as public, so execute is revoked from everyone and granted back only
-- to `service_role` — the same shape `list_streak_reminder_targets` already uses. It returns email
-- addresses and it can close accounts; `authenticated` has no business with any of it.
create or replace function public.dormancy_cohort(p_now timestamptz default now())
returns table (
  profile_id uuid,
  email text,
  first_name text,
  couple_id uuid,
  stage text,
  cohort_last_active_at timestamptz,
  delete_after timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with active_couple as (
    -- Only `active` couples bind two accounts into one cohort. A dissolved one is already on the
    -- archive timer and its members are each on their own clock again.
    select c.id, c.partner_a_id, c.partner_b_id
    from public.couples c
    where c.status = 'active'
  ),
  membership as (
    select p.id as profile_id, ac.id as couple_id
    from public.profiles p
    left join active_couple ac
      on p.id in (ac.partner_a_id, ac.partner_b_id)
  ),
  cohort as (
    select
      m.profile_id,
      m.couple_id,
      -- The couple's clock runs from whichever partner was here most recently; a solo account
      -- from its own timestamp. `max` over the members does both.
      case
        when m.couple_id is null then p.last_active_at
        else (
          select max(q.last_active_at)
          from public.profiles q
          join active_couple ac2 on ac2.id = m.couple_id
          where q.id in (ac2.partner_a_id, ac2.partner_b_id)
        )
      end as cohort_last_active_at
    from membership m
    join public.profiles p on p.id = m.profile_id
    -- Already-deleted accounts are somebody else's business: their profile is scrubbed and their
    -- auth row soft-deleted, and re-closing them would send mail to an address that is gone.
    where p.account_deleted_at is null
  ),
  due as (
    select
      c.profile_id,
      c.couple_id,
      c.cohort_last_active_at,
      c.cohort_last_active_at + private.dormancy_period() as delete_after
    from cohort c
  )
  select
    d.profile_id,
    u.email::text,
    p.first_name,
    d.couple_id,
    case
      when p_now >= d.delete_after then 'delete'
      when p_now >= d.delete_after - interval '7 days' then 'warn_7'
      else 'warn_30'
    end as stage,
    d.cohort_last_active_at,
    d.delete_after
  from due d
  join public.profiles p on p.id = d.profile_id
  join auth.users u on u.id = d.profile_id
  where
    -- Deletion is due, or a warning window has opened that this account has not been told about
    -- in the current cycle.
    p_now >= d.delete_after
    or (
      p_now >= d.delete_after - interval '7 days'
      and (p.dormancy_warned_at is null or p.dormancy_warned_at < d.delete_after - interval '7 days')
    )
    or (
      p_now >= d.delete_after - interval '30 days'
      and (p.dormancy_warned_at is null or p.dormancy_warned_at < d.delete_after - interval '30 days')
    );
$$;

comment on function public.dormancy_cohort(timestamptz) is
  'Profiles needing a dormancy warning or closure right now, one row each. Takes `p_now` so the '
  'tests can stand two years away without waiting. In `public` because PostgREST cannot see '
  '`private`, but executable only by service_role — it returns email addresses.';

-- ---------------------------------------------------------------------------
-- Closing one account
-- ---------------------------------------------------------------------------
--
-- Deliberately the same shape as `delete_own_account`, minus the `auth.uid()` it cannot have:
-- dissolve the active couple so the archive timer starts, drop this profile's own storage and
-- push tokens, scrub its identifying fields, leave the row. See 20260901001500 for why the row
-- itself has to survive — the FK cascade from profiles to couples would take the other partner's
-- shared history with it.
--
-- Soft-deleting the `auth.users` row is the caller's job, exactly as it is for `delete-account`:
-- it needs the admin API, which SQL does not have. Re-running this on an already-closed account
-- is a no-op, so a job that fails halfway can simply be run again.
create or replace function public.close_dormant_account(p_profile_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_couple_id uuid;
begin
  if p_profile_id is null then
    raise exception 'close_dormant_account requires a profile id';
  end if;

  if not exists (
    select 1 from public.profiles
    where id = p_profile_id and account_deleted_at is null
  ) then
    return;
  end if;

  for v_couple_id in
    select id from public.couples
    where (partner_a_id = p_profile_id or partner_b_id = p_profile_id) and status = 'active'
  loop
    update public.couples
    set status = 'dissolved', dissolved_at = now(), dissolved_by = p_profile_id
    where id = v_couple_id;
  end loop;

  perform set_config('storage.allow_delete_query', 'true', true);
  delete from storage.objects
   where bucket_id = 'avatars' and (storage.foldername(name))[1] = p_profile_id::text;
  delete from storage.objects
   where bucket_id = 'drawing-pads' and (storage.foldername(name))[2] = p_profile_id::text;

  delete from public.device_push_tokens where profile_id = p_profile_id;
  delete from public.live_activity_push_tokens where profile_id = p_profile_id;

  update public.profiles
  set first_name = 'Deleted User',
      avatar_path = null,
      partner_avatar_path = null,
      partner_name = null,
      home_place_id = null,
      partner_home_place_id = null,
      account_deleted_at = now()
  where id = p_profile_id;
end;
$$;

comment on function public.close_dormant_account(uuid) is
  'Closes one dormant account: dissolves its active couple (starting the usual 90-day archive '
  'timer, which remains the only thing that deletes shared content), drops its own storage and '
  'push tokens, scrubs its profile. Idempotent. The caller still has to soft-delete the auth row.';

-- ---------------------------------------------------------------------------
-- Recording that we warned somebody
-- ---------------------------------------------------------------------------
create or replace function public.mark_dormancy_warned(
  p_profile_ids uuid[],
  p_at timestamptz default now()
)
returns void
language sql
volatile
security definer
set search_path = public
as $$
  update public.profiles
  set dormancy_warned_at = p_at
  where id = any(p_profile_ids);
$$;

comment on function public.mark_dormancy_warned(uuid[], timestamptz) is
  'Stamps the accounts a warning has just gone out to, so the next run does not warn them again '
  'for the same window. `p_at` exists for the same reason dormancy_cohort takes `p_now`: a test '
  'has to be able to say "this one was warned during the 30-day window" and then check that the '
  '7-day warning still fires. Passing a stamp from outside the window under test would suppress '
  'every later window too, which is a bug the tests could not otherwise see.';

-- ---------------------------------------------------------------------------
-- Reachable by the job, and by nothing else
-- ---------------------------------------------------------------------------
--
-- `create function` grants execute to PUBLIC by default, so each of these has to be taken away
-- again explicitly. Without the revoke, being in `public` would mean any signed-in user could list
-- every dormant account's email address, or close an account outright.
revoke all on function public.dormancy_cohort(timestamptz) from public, anon, authenticated;
revoke all on function public.close_dormant_account(uuid) from public, anon, authenticated;
revoke all on function public.mark_dormancy_warned(uuid[], timestamptz) from public, anon, authenticated;

grant execute on function public.dormancy_cohort(timestamptz) to service_role;
grant execute on function public.close_dormant_account(uuid) to service_role;
grant execute on function public.mark_dormancy_warned(uuid[], timestamptz) to service_role;
