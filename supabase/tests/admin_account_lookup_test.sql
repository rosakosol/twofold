-- These functions are security definer and read `auth.users`, so the check inside each body is the
-- entire boundary between a support admin and everybody else's email address. Nothing outside them
-- is protecting anything.
--
-- What is worth pinning, in order of how badly it goes wrong:
--
--   * A non-support caller reads an account. A content admin — trusted to edit a trivia deck — is
--     the interesting case, because "is an admin" is the check somebody would write by reflex, and
--     it is the wrong one. That separation is the entire reason the roles were split.
--
--   * The detail call does not leave a trace. It is the call that turns an email address into a
--     person's subscription, partner and history; an unlogged one is indistinguishable from never
--     having happened.
--
--   * It returns content. The rule is status and structure, never content — flights counted and
--     never listed above all, because `flights.shared = false` is a promise the privacy policy
--     makes by name and `flight_privacy_test` spends twenty-one assertions keeping.

begin;
select plan(17);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('eeeeeeee-9999-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'support@lookup.test', 'x', now(), now(), now()),
  ('eeeeeeee-9999-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'content@lookup.test', 'x', now(), now(), now()),
  ('eeeeeeee-9999-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'Ada@Lookup.Test', 'x', now(), now(), now()),
  ('eeeeeeee-9999-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'bo@lookup.test', 'x', now(), now(), now());

insert into public.profiles (id, first_name) values
  ('eeeeeeee-9999-0000-0000-000000000001', 'Sam'),
  ('eeeeeeee-9999-0000-0000-000000000002', 'Con'),
  ('eeeeeeee-9999-0000-0000-000000000003', 'Ada'),
  ('eeeeeeee-9999-0000-0000-000000000004', 'Bo')
on conflict (id) do update set first_name = excluded.first_name;

insert into public.feedback_admins (profile_id, role) values
  ('eeeeeeee-9999-0000-0000-000000000001', 'support'),
  ('eeeeeeee-9999-0000-0000-000000000002', 'content');

insert into public.couples (id, partner_a_id, partner_b_id, status, started_dating_on)
values ('eeeeeeee-9999-cccc-0000-000000000001',
        'eeeeeeee-9999-0000-0000-000000000003', 'eeeeeeee-9999-0000-0000-000000000004',
        'active', date '2024-05-12');

-- ---------------------------------------------------------------------------
-- A support admin can find somebody
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'eeeeeeee-9999-0000-0000-000000000001', true);

-- The key a support email actually arrives with, and in the case it arrives in: people type their
-- address however they type it, and `auth.users` stores whatever they signed up with.
select is(
  (select profile_id from public.admin_lookup_account('ada@lookup.test')),
  'eeeeeeee-9999-0000-0000-000000000003'::uuid,
  'an email address finds the account, regardless of case'
);

select is(
  (select profile_id from public.admin_lookup_account('eeeeeeee-9999-0000-0000-000000000003')),
  'eeeeeeee-9999-0000-0000-000000000003'::uuid,
  'so does a profile id pasted from an earlier thread'
);

select ok(
  (select has_partner from public.admin_lookup_account('ada@lookup.test')),
  'and the result says whether they are paired, which decides what can be offered'
);

-- A query that looks uuid-ish but is not must not error the whole search — somebody will paste a
-- truncated id, and a failed cast would take the search box down rather than return nothing.
select is(
  (select count(*)::integer from public.admin_lookup_account('eeeeeeee-9999-0000')),
  0, 'a malformed id returns nothing rather than raising'
);

select is(
  (select count(*)::integer from public.admin_lookup_account('   ')),
  0, 'and a blank query returns nothing rather than everybody'
);

-- ---------------------------------------------------------------------------
-- The detail view
-- ---------------------------------------------------------------------------

select is(
  public.admin_account_detail('eeeeeeee-9999-0000-0000-000000000003') #>> '{auth,email}',
  'Ada@Lookup.Test', 'the detail carries the email, which is the fact PostgREST cannot serve'
);

select is(
  public.admin_account_detail('eeeeeeee-9999-0000-0000-000000000003') #>> '{couple,partner_first_name}',
  'Bo', 'and the partner, so support knows who else is affected'
);

select is(
  public.admin_account_detail('eeeeeeee-9999-0000-0000-000000000003') #>> '{counts,flights_tracked}',
  '0', 'flights are a count'
);

-- The rule, asserted as a rule rather than as a happy path. If a future edit adds a flight list,
-- a memory list or a document list to this payload, this fails.
select ok(
  not (public.admin_account_detail('eeeeeeee-9999-0000-0000-000000000003') ?| array['flights', 'memories', 'documents', 'photos', 'answers']),
  'and no content is returned at all — no flights, memories, documents, photos or answers'
);

select ok(
  public.admin_account_detail('eeeeeeee-9999-0000-0000-000000000003') #>> '{subscription,store}' is null,
  'an unseen storefront reads as unknown rather than as a value'
);

select ok(
  public.admin_account_detail('00000000-0000-0000-0000-00000000dead') is null,
  'an account that does not exist returns null rather than an empty shell'
);

-- ---------------------------------------------------------------------------
-- And leaves a trace
-- ---------------------------------------------------------------------------

-- A delta rather than an absolute count: asserting "there are N rows" would have to be edited
-- every time an assertion above adds another detail call, and an expected number that drifts with
-- unrelated edits is a test that gets relaxed rather than fixed. The property is that each view
-- adds exactly one row, so that is what is measured.
--
-- Across three statements, not one. A single statement sees a single snapshot, so a query that
-- counted, called, and counted again would observe the same number both times no matter what the
-- call wrote — it would pass for a function that logged nothing at all.
create temp table _audit_before as
  select count(*) as n from public.admin_audit_for_subject('eeeeeeee-9999-0000-0000-000000000003', 500);

select public.admin_account_detail('eeeeeeee-9999-0000-0000-000000000003');

select is(
  (select count(*) from public.admin_audit_for_subject('eeeeeeee-9999-0000-0000-000000000003', 500))
    - (select n from _audit_before),
  1::bigint, 'each detail view adds exactly one row to the log'
);

select is(
  (select action from public.admin_audit_for_subject('eeeeeeee-9999-0000-0000-000000000003') limit 1),
  'account.view', 'named for what it was'
);

select is(
  (select actor_email from public.admin_audit_for_subject('eeeeeeee-9999-0000-0000-000000000003') limit 1),
  'support@lookup.test', 'and attributed to whoever looked'
);

-- The search box is deliberately NOT logged: it returns only enough to pick a row, and recording
-- every keystroke-driven query would bury the reads that matter.
select is(
  (select count(*)::integer from public.admin_audit_for_subject('eeeeeeee-9999-0000-0000-000000000004')),
  0, 'searching alone leaves no trace, so the log stays worth reading'
);

-- ---------------------------------------------------------------------------
-- A content admin is not a support admin
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'eeeeeeee-9999-0000-0000-000000000002', true);

select throws_ok(
  $$ select * from public.admin_lookup_account('ada@lookup.test') $$,
  '42501', null, 'a content admin cannot look anybody up'
);

select throws_ok(
  $$ select public.admin_account_detail('eeeeeeee-9999-0000-0000-000000000003') $$,
  '42501', null, 'nor read an account'
);

reset role;
select * from finish();
rollback;
