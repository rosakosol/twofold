-- ---------------------------------------------------------------------------
-- invite_redemption_attempts: dead rows are pruned, live ones are not
-- ---------------------------------------------------------------------------
--
-- The table had no retention at all, so rows written to enforce a fifteen-minute rule were kept
-- forever. The prune runs from an AFTER INSERT statement trigger, which means the only thing that
-- grows the table is also the thing that cleans it — there is no job to monitor and nothing that
-- can silently stop.
--
-- The assertion that matters most is the second one: a prune that also removed rows still inside a
-- reader's window would quietly raise the effective rate limit, turning a retention change into a
-- security regression.

begin;
select plan(4);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values ('aaaaaaaa-9999-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ann@retention.test', 'x', now(), now(), now());

-- Staged with the trigger off. It fires on ANY insert, including this one, so staging with it
-- enabled would prune the old rows before a single assertion ran — the first version of this test
-- did that and failed asserting three rows existed.
alter table public.invite_redemption_attempts disable trigger trg_purge_old_invite_redemption_attempts;

-- Three rows spanning the boundary: one long dead, one just outside retention, one live.
insert into public.invite_redemption_attempts (redeemer_id, attempted_at) values
  ('aaaaaaaa-9999-0000-0000-000000000001', now() - interval '9 days'),
  ('aaaaaaaa-9999-0000-0000-000000000001', now() - interval '61 minutes'),
  ('aaaaaaaa-9999-0000-0000-000000000001', now() - interval '5 minutes');

select is(
  (select count(*)::int from public.invite_redemption_attempts
    where redeemer_id = 'aaaaaaaa-9999-0000-0000-000000000001'),
  3,
  'three rows are staged, spanning the retention boundary'
);

alter table public.invite_redemption_attempts enable trigger trg_purge_old_invite_redemption_attempts;

-- Any insert prunes. This is also what the RPCs do on every call, so the prune rides along with
-- the traffic that causes the growth.
insert into public.invite_redemption_attempts (redeemer_id) values ('aaaaaaaa-9999-0000-0000-000000000001');

select is(
  (select count(*)::int from public.invite_redemption_attempts
    where redeemer_id = 'aaaaaaaa-9999-0000-0000-000000000001'
      and attempted_at > now() - interval '15 minutes'),
  2,
  'both rows inside the readers 15-minute window survive — pruning must never raise the rate limit'
);

select is(
  (select count(*)::int from public.invite_redemption_attempts
    where redeemer_id = 'aaaaaaaa-9999-0000-0000-000000000001'),
  2,
  'and the two rows older than the retention hour are gone'
);

-- The prune is global rather than per-caller, so one person's traffic cleans up after everyone —
-- which is what stops rows accumulating under accounts that never come back.
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values ('bbbbbbbb-9999-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ben@retention.test', 'x', now(), now(), now());

insert into public.invite_redemption_attempts (redeemer_id, attempted_at)
values ('bbbbbbbb-9999-0000-0000-000000000002', now() - interval '3 hours');

insert into public.invite_redemption_attempts (redeemer_id) values ('aaaaaaaa-9999-0000-0000-000000000001');

select is(
  (select count(*)::int from public.invite_redemption_attempts
    where redeemer_id = 'bbbbbbbb-9999-0000-0000-000000000002'),
  0,
  'a dormant account s dead rows are pruned by someone else s traffic'
);

select * from finish();
rollback;
