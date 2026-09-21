-- The entitlement columns are server-owned.
--
-- `profiles.subscription_active` / `subscription_tier` / `subscription_checked_at` decide whether
-- someone has paid, and until 20260915000000 the client wrote them itself over PostgREST. A user
-- could PATCH their own row to `{"subscription_tier":"premium","subscription_active":true}` with
-- their own legitimate JWT and be Premium — and because `fetchSubscriptionActive` and
-- `private.couple_effective_tier` OR both partners' rows, that upgraded their partner too.
--
-- What has to stay true, and is pinned below: an `authenticated` session cannot move any of the
-- three, on its own row, by any shape of statement; it can still edit the rest of its profile
-- exactly as before; a mixed update fails whole rather than applying the innocent half; and
-- service_role — where the RevenueCat webhook will write from — is unaffected.
--
-- The last two tests are the point of the migration's design. A column REVOKE alone does not hold
-- here (a table-level `grant all` is not decomposable into column grants, so revoking a column from
-- a role that holds table-level UPDATE is a no-op), and even after the table-level grant is
-- removed, one `grant all on all tables in schema public` — the statement 20260911000100 already
-- contains — would restore it. So the trigger is tested with those grants deliberately handed back.

begin;
select plan(16);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-3333-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@entitlement.test', 'x', now(), now(), now()),
  ('bbbbbbbb-3333-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@entitlement.test', 'x', now(), now(), now());

-- A trigger on auth.users already created these rows, so this fills in the fields the
-- tests care about rather than inserting fresh.
insert into public.profiles (id, first_name) values
  ('aaaaaaaa-3333-0000-0000-000000000001', 'Ada'),
  ('bbbbbbbb-3333-0000-0000-000000000002', 'Mel')
on conflict (id) do update set first_name = excluded.first_name;

-- ---------------------------------------------------------------------------
-- An authenticated user, on their OWN row — the row RLS genuinely lets them update.
-- ---------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-3333-0000-0000-000000000001', true);

select throws_ok(
  $$update public.profiles set subscription_active = true where id = 'aaaaaaaa-3333-0000-0000-000000000001'$$,
  '42501',
  null,
  'a user cannot switch on their own subscription_active'
);

select throws_ok(
  $$update public.profiles set subscription_tier = 'premium' where id = 'aaaaaaaa-3333-0000-0000-000000000001'$$,
  '42501',
  null,
  'a user cannot set their own subscription_tier to premium'
);

select throws_ok(
  $$update public.profiles set subscription_checked_at = now() where id = 'aaaaaaaa-3333-0000-0000-000000000001'$$,
  '42501',
  null,
  'a user cannot stamp their own subscription_checked_at'
);

-- `subscription_store` decides what a web account screen offers. A client that could set it could
-- claim its App Store subscription was bought on the website — and then be handed a cancel button
-- that reaches for a Stripe subscription which does not exist.
select throws_ok(
  $$update public.profiles set subscription_store = 'stripe' where id = 'aaaaaaaa-3333-0000-0000-000000000001'$$,
  '42501',
  null,
  'a user cannot claim which storefront sold their subscription'
);

-- Reading it is fine and necessary — the account screen has to know what to offer. SELECT on
-- profiles is table-level, so a new column is readable without a new grant; this pins that,
-- because a screen that cannot read this column shows everyone the wrong options.
select ok(
  has_column_privilege('authenticated', 'public.profiles', 'subscription_store', 'SELECT'),
  'but can read it, which is what the account screen needs'
);

-- The real payload: `updateSubscriptionStatus` writes all three in one PATCH.
select throws_ok(
  $$update public.profiles
      set subscription_active = true, subscription_tier = 'premium', subscription_checked_at = now()
    where id = 'aaaaaaaa-3333-0000-0000-000000000001'$$,
  '42501',
  null,
  'the exact client entitlement write is rejected'
);

-- ---------------------------------------------------------------------------
-- Ordinary profile editing is untouched. If this fails the migration is too blunt: renaming
-- yourself, setting a timezone and every notification preference go through this same policy.
-- ---------------------------------------------------------------------------
update public.profiles set first_name = 'Adaline' where id = 'aaaaaaaa-3333-0000-0000-000000000001';
select is(
  (select first_name from public.profiles where id = 'aaaaaaaa-3333-0000-0000-000000000001'),
  'Adaline',
  'a user can still rename themselves on their own row'
);

-- ---------------------------------------------------------------------------
-- A mixed update must fail whole. Smuggling the entitlement in beside a legitimate column is the
-- obvious next attempt, and "the tier was refused but the name went through" would mean the
-- statement was applied in parts.
-- ---------------------------------------------------------------------------
select throws_ok(
  $$update public.profiles
      set first_name = 'Smuggler', subscription_tier = 'premium'
    where id = 'aaaaaaaa-3333-0000-0000-000000000001'$$,
  '42501',
  null,
  'an update mixing a legal column with subscription_tier is rejected'
);
select is(
  (select first_name from public.profiles where id = 'aaaaaaaa-3333-0000-0000-000000000001'),
  'Adaline',
  'the legal half of the rejected update was not applied'
);
select is(
  (select subscription_tier from public.profiles where id = 'aaaaaaaa-3333-0000-0000-000000000001'),
  null,
  'and the tier is still unset'
);

-- ---------------------------------------------------------------------------
-- The trigger, not the grants, is the guarantee. Hand the table-level UPDATE straight back — the
-- state 20260911000100's `grant all on all tables in schema public` would leave behind — and the
-- write must still be refused.
-- ---------------------------------------------------------------------------
reset role;
grant all on public.profiles to anon, authenticated;

select ok(
  has_column_privilege('authenticated', 'public.profiles', 'subscription_tier', 'UPDATE'),
  'a blanket grant does put the column privilege back, so the revoke alone would not have held'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-3333-0000-0000-000000000001', true);
select throws_ok(
  $$update public.profiles
      set subscription_active = true, subscription_tier = 'premium'
    where id = 'aaaaaaaa-3333-0000-0000-000000000001'$$,
  '42501',
  null,
  'the trigger still refuses the write after a blanket grant restores the privilege'
);

-- The new column is only safe because it is named in the trigger. Until this migration it was
-- protected by the column grants alone, which is precisely what the blanket grant above undoes.
select throws_ok(
  $$update public.profiles set subscription_store = 'stripe' where id = 'aaaaaaaa-3333-0000-0000-000000000001'$$,
  '42501',
  null,
  'and refuses subscription_store too, which grants alone would not have'
);

-- ---------------------------------------------------------------------------
-- service_role writes all three. This is the path the RevenueCat webhook will use; if it were
-- caught by the guard, the fix would ship a working exploit block and a broken subscription.
-- ---------------------------------------------------------------------------
reset role;
set local role service_role;
update public.profiles
  set subscription_active = true, subscription_tier = 'premium', subscription_checked_at = '2026-09-15T00:00:00Z',
      subscription_store = 'app_store'
where id = 'bbbbbbbb-3333-0000-0000-000000000002';

select results_eq(
  $$select subscription_active, subscription_tier, subscription_checked_at
      from public.profiles where id = 'bbbbbbbb-3333-0000-0000-000000000002'$$,
  $$values (true, 'premium', '2026-09-15T00:00:00Z'::timestamptz)$$,
  'service_role can still write all three entitlement columns'
);

select is(
  (select subscription_store from public.profiles where id = 'bbbbbbbb-3333-0000-0000-000000000002'),
  'app_store',
  'service_role can record the storefront, which is how the webhook writes it'
);

-- And can take them away again when a subscription lapses.
update public.profiles set subscription_active = false where id = 'bbbbbbbb-3333-0000-0000-000000000002';
select is(
  (select subscription_active from public.profiles where id = 'bbbbbbbb-3333-0000-0000-000000000002'),
  false,
  'service_role can clear subscription_active on a lapse'
);

reset role;
select * from finish();
rollback;
