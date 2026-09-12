-- An override raises one couple's flight allowance and nobody else's.
--
-- Four ways this goes wrong, and each either costs money or takes something away:
--
--   * The override does not apply, and the account it was written for still hits the cap.
--   * It applies to everyone, and every couple gets an uncapped AeroAPI bill.
--   * It leaks into the tier, handing out premium decks and Hard sudoku with it.
--   * It is reachable from the client, which makes the cap advisory.

begin;
select plan(9);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-1818-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'over@limit.test', 'x', now(), now(), now()),
  ('bbbbbbbb-1818-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'partner@limit.test', 'x', now(), now(), now()),
  ('dddddddd-1818-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'plain@limit.test', 'x', now(), now(), now()),
  ('eeeeeeee-1818-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'plain2@limit.test', 'x', now(), now(), now());

insert into public.profiles (id, first_name, timezone, subscription_active, subscription_tier) values
  ('aaaaaaaa-1818-0000-0000-000000000001', 'Ada', 'UTC', false, null),
  ('bbbbbbbb-1818-0000-0000-000000000002', 'Mel', 'UTC', false, null),
  ('dddddddd-1818-0000-0000-000000000004', 'Dev', 'UTC', false, null),
  ('eeeeeeee-1818-0000-0000-000000000005', 'Eve', 'UTC', false, null)
on conflict (id) do update
  set first_name = excluded.first_name, timezone = excluded.timezone,
      subscription_active = excluded.subscription_active,
      subscription_tier = excluded.subscription_tier;

insert into public.couples (id, partner_a_id, partner_b_id) values
  ('cccccccc-1818-0000-0000-000000000003', 'aaaaaaaa-1818-0000-0000-000000000001', 'bbbbbbbb-1818-0000-0000-000000000002'),
  ('cccccccc-1818-0000-0000-000000000013', 'dddddddd-1818-0000-0000-000000000004', 'eeeeeeee-1818-0000-0000-000000000005');

-- MARK: before any override

select is(
  private.flight_limit_for_couple('cccccccc-1818-0000-0000-000000000003'),
  2,
  'with no override a couple gets the tier default'
);

-- MARK: an override on one partner

insert into private.flight_limit_overrides (profile_id, monthly_limit, note)
values ('aaaaaaaa-1818-0000-0000-000000000001', 100000, 'test');

select is(
  private.flight_limit_for_couple('cccccccc-1818-0000-0000-000000000003'),
  100000,
  'the override replaces the tier default'
);

select is(
  private.flight_limit_for_couple('cccccccc-1818-0000-0000-000000000013'),
  2,
  'and applies to that couple only — everybody else still has the cap'
);

-- The allowance is the couple's, so the partner who holds no override draws on the same raised
-- pool. Asked as that partner, through the function the app actually calls — this is the half
-- that would silently not work if the lookup keyed on the caller instead of the couple.
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-1818-0000-0000-000000000002"}';

select is(
  (public.flight_allowance('cccccccc-1818-0000-0000-000000000003') ->> 'limit')::int,
  100000,
  'the partner without the override sees the same raised allowance'
);

set local role postgres;

-- MARK: it is a spending limit, not a tier

select is(
  private.couple_effective_tier('cccccccc-1818-0000-0000-000000000003'),
  'plus',
  'an override does not promote the couple to premium'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-1818-0000-0000-000000000001"}';

select is(
  public.flight_allowance('cccccccc-1818-0000-0000-000000000003') ->> 'tier',
  'plus',
  'and the allowance still reports the real tier rather than renaming their plan'
);

set local role postgres;

-- MARK: both partners, and the larger wins

insert into private.flight_limit_overrides (profile_id, monthly_limit, note)
values ('bbbbbbbb-1818-0000-0000-000000000002', 7, 'test');

select is(
  private.flight_limit_for_couple('cccccccc-1818-0000-0000-000000000003'),
  100000,
  'two overrides on one couple take the larger, never the smaller'
);

-- MARK: out of the client's reach

-- `config.toml` serves `public` and `graphql_public` only, so this table is not addressable over
-- PostgREST at all. The grant is checked as the second line of defence behind that.
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-1818-0000-0000-000000000001"}';

select throws_ok(
  $$ insert into private.flight_limit_overrides (profile_id, monthly_limit) values ('aaaaaaaa-1818-0000-0000-000000000001', 999999) $$,
  '42501',
  NULL,
  'a signed-in client cannot write itself an allowance'
);

select throws_ok(
  $$ select * from private.flight_limit_overrides $$,
  '42501',
  NULL,
  'nor read who has one'
);

select * from finish();
rollback;
