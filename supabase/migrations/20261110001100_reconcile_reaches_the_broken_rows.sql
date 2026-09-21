-- The nightly reconcile skips exactly the accounts that need it.
--
-- `reconcile-subscriptions` selects its cohort with
--
--   .or(`subscription_active.eq.true,subscription_checked_at.gte.${cutoff}`)
--
-- so it refreshes people who are already recorded as paying, and people checked recently. A
-- profile sitting at `subscription_active = false` with `subscription_checked_at = null` matches
-- neither. That is not an edge case — it is the precise shape of the bug this exists to repair.
--
-- How a row gets into that state: a purchase made before `applyOnboardingAccount` called
-- `identifyWithRevenueCat` attached to `$RCAnonymousID:…` rather than to the Supabase user, so the
-- webhook had no resolvable id and wrote nothing. The buyer never notices — the SDK holds the
-- entitlement on the device and `resolvedSubscriptionActive` ORs it in — but their partner has
-- only the row to go on, and the row says no. That is the "Max pays and Jules is told there is no
-- subscription" report, and now the same thing for a second pair of testers.
--
-- The app-side fixes exist (identify before the paywall; re-sync when the device is entitled and
-- the row disagrees) and both need a release. This one does not, and it is the better layer
-- anyway: it does not depend on the person who bought the subscription opening the app.
--
-- ---------------------------------------------------------------------------
-- Scoped to couples where nobody is recorded as paying
-- ---------------------------------------------------------------------------
--
-- The obvious fix — add `subscription_checked_at.is.null` — would sweep in every profile that has
-- never had a subscription, which is most of them, and ask RevenueCat about each one nightly
-- forever.
--
-- The population that actually suffers is narrower: a couple exists, and neither member's row says
-- active. Entitlement is read as an OR across both partners, so if either row were true the couple
-- would already have access and nobody would be locked out. A solo account in this state is
-- invisible to itself — the device entitlement covers it — and has no partner to fail.
--
-- The set therefore drains: as soon as a probe finds a real subscription, that couple has an active
-- row and stops matching. What does not drain is a genuinely free couple, so `subscription_probed_at`
-- bounds them to one probe a week rather than one a night. It is stamped whatever the outcome,
-- which is why it cannot be `subscription_checked_at`: that column means "this state is
-- RevenueCat's as of this instant", and writing it after a probe that learned nothing would be a
-- lie the freshness guard then trusts.

alter table public.profiles
  add column if not exists subscription_probed_at timestamptz;

comment on column public.profiles.subscription_probed_at is
  'When reconcile-subscriptions last asked RevenueCat about this profile, whatever the answer. '
  'Distinct from subscription_checked_at, which records the instant a *state* came from and is '
  'only written when one did. Exists to stop the repair cohort re-probing the same free couples.';

-- Deliberately no grant. 20260915000000 revoked table-level UPDATE on profiles and re-granted per
-- column, so a column nobody names is unwritable by clients — which is what we want here, and the
-- opposite of the trap 20261106000000 fell into by needing one.

create or replace function public.subscriptions_to_reconcile(p_checked_cutoff timestamptz)
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  -- Already recorded as paying: kept fresh so a cancellation lands.
  select id from public.profiles where subscription_active

  union

  -- Checked recently: catches anything mid-change.
  select id from public.profiles where subscription_checked_at >= p_checked_cutoff

  union

  -- The repair cohort. Both members of an active couple where neither row says active, and which
  -- has not been probed in the last week.
  select p.id
  from public.profiles p
  join public.couples c
    on (c.partner_a_id = p.id or c.partner_b_id = p.id)
   and c.status = 'active'
  where not exists (
      select 1 from public.profiles other
      where other.id in (c.partner_a_id, c.partner_b_id)
        and other.subscription_active
    )
    and (p.subscription_probed_at is null or p.subscription_probed_at < now() - interval '7 days')
$$;

create or replace function public.mark_subscriptions_probed(p_ids uuid[])
returns void
language sql
security definer
set search_path = public
as $$
  update public.profiles
  set subscription_probed_at = now()
  where id = any(p_ids);
$$;

-- In `public` rather than `private`, because PostgREST only exposes `public` and the reconcile job
-- reaches these through it. Closed to everyone but the service role, in the full three-name form
-- that 20261108000000 established — `from public` alone leaves the grants Supabase's default
-- privileges hand anon and authenticated, which is how a function reads as locked and is not.
revoke all on function public.subscriptions_to_reconcile(timestamptz) from public, anon, authenticated;
revoke all on function public.mark_subscriptions_probed(uuid[]) from public, anon, authenticated;
grant execute on function public.subscriptions_to_reconcile(timestamptz) to service_role;
grant execute on function public.mark_subscriptions_probed(uuid[]) to service_role;
