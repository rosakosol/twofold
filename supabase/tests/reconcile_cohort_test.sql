-- The nightly reconcile has to reach the rows that are wrong, which is the one thing it did not do.
--
-- Its cohort was "already recorded as paying, or checked recently". A profile at
-- `subscription_active = false` with a null `subscription_checked_at` matched neither — and that is
-- exactly the row a purchase leaves behind when it attached to an anonymous RevenueCat id: the
-- webhook had no resolvable user, so it wrote nothing at all. The buyer never notices, because the
-- device holds the entitlement. Their partner has only the row.
--
-- So the assertion that matters is that a couple with two false rows is now in the cohort, and the
-- ones that keep it from being "every profile, nightly, forever" are the ones after it.

begin;
select plan(7);

create extension if not exists pgtap;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
select id::uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', id || '@recon.test', 'x', now(), now()
from (values
  ('aaaa0000-0000-4000-8000-000000000001'), ('aaaa0000-0000-4000-8000-000000000002'),
  ('bbbb0000-0000-4000-8000-000000000001'), ('bbbb0000-0000-4000-8000-000000000002'),
  ('cccc0000-0000-4000-8000-000000000001')
) as t(id)
on conflict do nothing;

-- Couple A: nobody recorded as paying. The broken shape.
insert into public.couples (id, partner_a_id, partner_b_id, status) values
  ('a0000000-0000-4000-8000-00000000000a',
   'aaaa0000-0000-4000-8000-000000000001', 'aaaa0000-0000-4000-8000-000000000002', 'active');

-- Couple B: one partner recorded as paying, so the couple already has access via the OR.
insert into public.couples (id, partner_a_id, partner_b_id, status) values
  ('b0000000-0000-4000-8000-00000000000b',
   'bbbb0000-0000-4000-8000-000000000001', 'bbbb0000-0000-4000-8000-000000000002', 'active');
update public.profiles set subscription_active = true
where id = 'bbbb0000-0000-4000-8000-000000000001';

-- ---------------------------------------------------------------------------
-- The repair cohort
-- ---------------------------------------------------------------------------

select ok(
  'aaaa0000-0000-4000-8000-000000000001'::uuid
    in (select public.subscriptions_to_reconcile(now() - interval '3 days')),
  'a member of a couple where nobody is recorded as paying is reconciled'
);
select ok(
  'aaaa0000-0000-4000-8000-000000000002'::uuid
    in (select public.subscriptions_to_reconcile(now() - interval '3 days')),
  'and so is their partner, because either row could be the one that is wrong'
);

-- The old cohort, still covered.
select ok(
  'bbbb0000-0000-4000-8000-000000000001'::uuid
    in (select public.subscriptions_to_reconcile(now() - interval '3 days')),
  'an active subscriber is still refreshed, so a cancellation still lands'
);

-- ---------------------------------------------------------------------------
-- What keeps it from being every profile, every night
-- ---------------------------------------------------------------------------

select ok(
  'bbbb0000-0000-4000-8000-000000000002'::uuid
    not in (select public.subscriptions_to_reconcile(now() - interval '3 days')),
  'the non-paying half of a couple that already has access is not probed'
);

select ok(
  'cccc0000-0000-4000-8000-000000000001'::uuid
    not in (select public.subscriptions_to_reconcile(now() - interval '3 days')),
  'and neither is a profile in no couple at all, which has nobody to fail'
);

-- Probing stamps regardless of outcome, so a genuinely free couple drops out for a week rather
-- than being asked about nightly forever.
select public.mark_subscriptions_probed(array[
  'aaaa0000-0000-4000-8000-000000000001', 'aaaa0000-0000-4000-8000-000000000002'
]::uuid[]);

select ok(
  'aaaa0000-0000-4000-8000-000000000001'::uuid
    not in (select public.subscriptions_to_reconcile(now() - interval '3 days')),
  'a couple just probed is not probed again the next night'
);

update public.profiles set subscription_probed_at = now() - interval '8 days'
where id in ('aaaa0000-0000-4000-8000-000000000001', 'aaaa0000-0000-4000-8000-000000000002');

select ok(
  'aaaa0000-0000-4000-8000-000000000001'::uuid
    in (select public.subscriptions_to_reconcile(now() - interval '3 days')),
  'but it comes back round a week later, in case they subscribed since'
);

select * from finish();
rollback;
