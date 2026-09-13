-- Buying a Relationship Record export.
--
-- This is a ledger of things people paid for, so the properties worth holding are the ones that
-- cost someone either money or a feature they bought:
--
--   1. A redelivered webhook grants one credit, not two. RevenueCat retries, and a consumable
--      granted twice is one given away.
--   2. Spending takes exactly one, and the second attempt with an empty balance fails rather than
--      exporting for free.
--   3. A credit belongs to its buyer. The partner does not inherit it — which is the one place
--      this deliberately differs from streak_repair_credits, where the couple owns the credit.
--   4. Nobody can write the table from the client. A grantable credit is a free feature.

begin;
select plan(9);

create extension if not exists pgtap;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('cccccccc-8888-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ana@rec.test', 'x', now(), now()),
  ('cccccccc-8888-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'bo@rec.test',  'x', now(), now())
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Granting is idempotent
-- ---------------------------------------------------------------------------

select is(
  private.grant_record_export_credit('cccccccc-8888-0000-0000-00000000000a', 'txn-rec-1'),
  true,
  'a new transaction grants a credit'
);

select is(
  private.grant_record_export_credit('cccccccc-8888-0000-0000-00000000000a', 'txn-rec-1'),
  false,
  'redelivering the same transaction grants nothing and says so'
);

select is(
  (select count(*)::int from public.record_export_credits where profile_id = 'cccccccc-8888-0000-0000-00000000000a'),
  1,
  'one purchase, one credit, however many times the webhook fires'
);

-- ---------------------------------------------------------------------------
-- Spending
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-8888-0000-0000-00000000000a","role":"authenticated"}';

select is(
  public.spend_record_export_credit(),
  true,
  'spending with a credit in hand succeeds'
);

select is(
  public.spend_record_export_credit(),
  false,
  'spending again with an empty balance fails rather than exporting for free'
);

select is(
  (select count(*)::int from public.record_export_credits where consumed_at is not null),
  1,
  'exactly one credit was consumed'
);

-- ---------------------------------------------------------------------------
-- A credit belongs to its buyer
-- ---------------------------------------------------------------------------

reset role;
select private.grant_record_export_credit('cccccccc-8888-0000-0000-00000000000a', 'txn-rec-2');

set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-8888-0000-0000-00000000000b","role":"authenticated"}';

select is(
  public.spend_record_export_credit(),
  false,
  'a partner cannot spend a credit somebody else paid for'
);

select is(
  (select count(*)::int from public.record_export_credits),
  0,
  'and cannot even see it'
);

-- ---------------------------------------------------------------------------
-- Nobody grants themselves one
-- ---------------------------------------------------------------------------

select throws_ok(
  $$ insert into public.record_export_credits (profile_id, transaction_id)
     values ('cccccccc-8888-0000-0000-00000000000b', 'forged') $$,
  '42501',
  NULL,
  'a client cannot write itself a credit'
);

reset role;
select * from finish();
rollback;
